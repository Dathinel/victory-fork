//! Thread-group convergence for branches taken by multiple waves.

use super::*;

fn exits_succ(st: &Structured) -> Option<Vec<Vec<usize>>> {
    let n = st.exits.len();
    let mut succ: Vec<Vec<usize>> = vec![Vec::new(); n];
    for (b, e) in st.exits.iter().enumerate() {
        match *e {
            LaneExit::Jump(t) => succ[b].push(t),
            LaneExit::Branch { taken, not_taken, .. } => {
                succ[b].push(taken);
                succ[b].push(not_taken);
            }
            LaneExit::End => {}
            LaneExit::Indirect => return None,
        }
    }
    Some(succ)
}

fn postdominators(succ: &[Vec<usize>]) -> Vec<Vec<u64>> {
    let n = succ.len();
    let words = n.div_ceil(64).max(1);
    let full = vec![u64::MAX; words];
    let mut pdom: Vec<Vec<u64>> = (0..n)
        .map(|b| {
            if succ[b].is_empty() {
                let mut v = vec![0; words];
                v[b / 64] |= 1 << (b % 64);
                v
            } else {
                full.clone()
            }
        })
        .collect();
    let mut changed = true;
    while changed {
        changed = false;
        for b in (0..n).rev() {
            if succ[b].is_empty() {
                continue;
            }
            let mut v = full.clone();
            for &t in &succ[b] {
                for w in 0..words {
                    v[w] &= pdom[t][w];
                }
            }
            v[b / 64] |= 1 << (b % 64);
            if v != pdom[b] {
                pdom[b] = v;
                changed = true;
            }
        }
    }
    pdom
}

fn mark_branch_region(succ: &[Vec<usize>], pdom: &[Vec<u64>], d: usize, seen: &mut [bool]) {
    let mut stack: Vec<usize> = succ[d].clone();
    while let Some(b) = stack.pop() {
        if seen[b] || (pdom[d][b / 64] >> (b % 64)) & 1 == 1 {
            continue;
        }
        seen[b] = true;
        stack.extend(succ[b].iter().copied());
    }
}

/// Every per-lane branch (by its block) with its region: the blocks reachable from it that do
/// not post-dominate it, which only some lanes run. Not the branches the wave takes together
/// ([`Structured::wide`]), nor those on scalar conditions. None with an indirect exit.
pub(super) fn lane_regions(st: &Structured) -> Option<Vec<(usize, Vec<bool>)>> {
    let n = st.exits.len();
    let succ = exits_succ(st)?;
    let pdom = postdominators(&succ);
    let mut regions = Vec::new();
    for (d, e) in st.exits.iter().enumerate() {
        let LaneExit::Branch { when, .. } = *e else { continue };
        if st.wide.contains(&d) || st.bools.support(when).iter().all(|a| matches!(a, Atom::Uniform(_))) {
            continue; // a wave-wide or uniform branch: all lanes go the same way
        }
        let mut seen = vec![false; n];
        mark_branch_region(&succ, &pdom, d, &mut seen);
        regions.push((d, seen));
    }
    Some(regions)
}

/// Per IR block in a multi-wave compute group: whether every wave of the threadgroup runs it
/// together (lies outside both un-widened lane branches and scalar branches whose condition
/// is not provably threadgroup-uniform). None with an indirect exit.
pub(super) fn all_group_blocks(p: &Program, st: &Structured) -> Option<Vec<bool>> {
    let n = st.exits.len();
    let succ = exits_succ(st)?;
    let pdom = postdominators(&succ);
    let order = crate::ir::reverse_postorder(&p.blocks);
    let mut in_order = vec![false; n];
    for &b in &order {
        in_order[b] = true;
    }
    let mut assumed_s: HashSet<Value> = HashSet::new();
    for block in &p.blocks {
        for phi in &block.phis {
            if matches!(phi.reg, Reg::S(_) | Reg::Scc) {
                assumed_s.insert(phi.value);
            }
        }
    }
    loop {
        let mut uniform_s: HashSet<Value> = p
            .inputs
            .iter()
            .filter_map(|&(r, v)| match r {
                Reg::S(c) if c < 106 => Some(v),
                _ => None,
            })
            .collect();
        for &b in &order {
            for phi in &p.blocks[b].phis {
                if assumed_s.contains(&phi.value) {
                    uniform_s.insert(phi.value);
                }
            }
            for inst in &p.blocks[b].insts {
                let name = inst.name();
                let produces_uniform = match &inst.fields {
                    Fields::Smem { .. } => {
                        !name.contains("atomic")
                            && inst.reads.iter().all(|&(_, v)| uniform_s.contains(&v))
                    }
                    Fields::Sop { .. } => {
                        !name.starts_with("s_getreg")
                            && inst
                                .reads
                                .iter()
                                .all(|&(r, v)| matches!(r, Reg::S(_) | Reg::Scc) && uniform_s.contains(&v))
                    }
                    _ => false,
                };
                if produces_uniform {
                    for &(r, w) in &inst.writes {
                        if matches!(r, Reg::S(_) | Reg::Scc) {
                            uniform_s.insert(w);
                        }
                    }
                }
            }
        }
        let mut diverged = vec![false; n];
        for (d, e) in st.exits.iter().enumerate() {
            if !in_order[d] || st.wide.contains(&d) {
                continue;
            }
            let LaneExit::Branch { when, .. } = *e else {
                continue;
            };
            let group_uniform = st
                .bools
                .support(when)
                .iter()
                .all(|a| matches!(a, Atom::Uniform(v) if uniform_s.contains(v)));
            if !group_uniform {
                mark_branch_region(&succ, &pdom, d, &mut diverged);
            }
        }
        let mut changed = false;
        for &b in &order {
            let block = &p.blocks[b];
            let preds_uniform = block
                .preds
                .iter()
                .all(|&q| !in_order[q] || !diverged[q]);
            for phi in &block.phis {
                if assumed_s.contains(&phi.value)
                    && (!preds_uniform || !phi.args.iter().all(|a| uniform_s.contains(a)))
                {
                    assumed_s.remove(&phi.value);
                    changed = true;
                }
            }
        }
        if !changed {
            return Some(diverged.into_iter().map(|d| !d).collect());
        }
    }
}
