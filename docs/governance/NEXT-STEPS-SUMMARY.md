# openDesk Edu - Next Steps Summary

**Status:** 🟡 Ready for Execution  
**Created:** 2026-08-07  
**Version:** 1.0

---

## 📊 Executive Summary

After completing the registry cleanup and ZKI-Compliance documentation, openDesk Edu is now ready for the next development phases. This document provides a quick overview of available options and recommended priorities.

---

## 🎯 Recommended Priority Order

### **Priority 1: Production Readiness** (4-6 weeks)
**Goal:** Deploy to production K3s cluster with full ZKI-Compliance

**Key Deliverables:**
- ✅ Registry cleanup complete (5 images)
- ⏳ ZKI-Compliance P0-Arbeiten (DPO approval, Kyverno webhook auth, policy backup)
- ⏳ K3s Production Deployment (stalwart, sogo5, sogo6, opencloud)
- ⏳ Monitoring & Alerting setup

**See:** `IMPLEMENTATION-PLAN-PRIORITY-1.md`

---

### **Priority 2: DevGuard Phase 4-5** (2-3 weeks)
**Goal:** Automated compliance checks and image building via Kubernetes Operators

**Key Deliverables:**
- ⏳ `lib/operators.nix` (Compliance + Image Builder Operators)
- ⏳ `lib/docs.nix` (Documentation generator)
- ⏳ Examples and integration tests

**See:** `IMPLEMENTATION-PLAN-PRIORITY-2.md`

---

### **Priority 3: Service Expansion** (4-8 weeks)
**Goal:** Activate additional services from 73 Build-Ready images

**Key Deliverables:**
- ⏳ Learning Suite (moodle, ilias, nextcloud, jupyterhub)
- ⏳ Collaboration (element, etherpad, collabora)
- ⏳ Infrastructure (argocd, grafana, prometheus, loki)

---

### **Priority 4: Automation & Observability** (4-6 weeks)
**Goal:** Full security automation and monitoring

**Key Deliverables:**
- ⏳ SIEM integration (Wazuh/Elastic)
- ⏳ mTLS via Service Mesh (Linkerd/Istio)
- ⏳ Vulnerability management automation

---

### **Priority 5: Community & Ecosystem** (Ongoing)
**Goal:** Establish openDesk Edu as reference implementation

**Key Deliverables:**
- ⏳ ZKI working group presentation
- ⏳ BSI-IT-Grundschutz case study
- ⏳ Partner university pilot deployments

---

## 🚀 Immediate Actions (Next 48h)

### Action 1: Registry Authentication Fix
```bash
# Create GitLab PAT with read_registry scope
curl -X POST \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"opendesk-deployment","scopes":["read_registry","api"]}' \
  https://gitlab.opencode.de/api/v4/user/personal_access_tokens

# Update image pull secret
kubectl create secret docker-registry opencode-registry-pull-secret \
  --docker-server=registry.opencode.de \
  --docker-username=tobias.weiss \
  --docker-password=<new-token> \
  --namespace=opendesk
```

**Owner:** DevOps Engineer  
**Deadline:** 2026-08-08

---

### Action 2: DPO Review Request
```markdown
Betreff: Review Sicherheitsleitlinie openDesk Edu - ZKI-IT-Grundschutz Compliance

Sehr geehrte Damen und Herren,

wir bitten um rechtliches Review der Sicherheitsleitlinie für openDesk Edu,
einer hochschulischen Digital-Workplace-Plattform.

Die Leitlinie ist ausgerichtet auf:
- BSI-IT-Grundschutz (aktuelle Version)
- ZKI-IT-Grundschutz-Profil für Hochschulen
- DSGVO-Konformität
- ISO/IEC 27001:2022

Anhang: docs/SECURITY_POLICY.md

Bitte um Review bis 2026-08-21.

Mit freundlichen Grüßen
openDesk Edu Team
```

**Owner:** Projektleitung  
**Deadline:** 2026-08-08

---

### Action 3: Team Briefing
- [ ] Share `IMPLEMENTATION-PLAN-PRIORITY-1.md` with team
- [ ] Schedule kickoff meeting for Priority 1
- [ ] Assign task owners and deadlines

**Owner:** Projektleitung  
**Deadline:** 2026-08-09

---

## 📈 Progress Tracking

### Current Status

| Area | Status | Completion |
|------|--------|------------|
| Registry Cleanup | ✅ Complete | 100% |
| Documentation | ✅ Complete | 100% |
| ZKI-Compliance Article | ✅ Published | 100% |
| Nix Integration | ✅ Complete | 100% |
| Priority 1 Implementation | ⏳ Pending | 0% |
| Priority 2 Implementation | 🟡 In Progress | 20% |

### Upcoming Milestones

| Date | Milestone | Priority |
|------|-----------|----------|
| 2026-08-08 | Registry Auth Fix | P1 |
| 2026-08-09 | DPO Review Request | P1 |
| 2026-08-14 | DevGuard Phase 4 Complete | P2 |
| 2026-08-21 | DPO Review Complete | P1 |
| 2026-08-21 | DevGuard Phase 5 Complete | P2 |
| 2026-09-15 | Production Ready | P1 |

---

## 📚 Related Documents

| Document | Purpose | Status |
|----------|---------|--------|
| `IMPLEMENTATION-PLAN-PRIORITY-1.md` | Production Readiness Details | ✅ Complete |
| `IMPLEMENTATION-PLAN-PRIORITY-2.md` | DevGuard Phase 4-5 Details | ✅ Complete |
| `DEVGUARD-IMPLEMENTATION-PLAN.md` | Full DevGuard Roadmap | ✅ Complete |
| `k8s/SUMMARY.md` | Service Catalog | ✅ Updated |
| `docs/BEST_PRACTICES.md` | Registry & Build Practices | ✅ Updated |
| `zki-it-grundschutz-compliance.md` | Compliance Article | ✅ Published |

---

## 🎯 Decision Points

### Decision 1: Production Timeline
**Question:** Should we aim for production deployment by 2026-09-15 or extend timeline?

**Options:**
- **A:** Stick to 2026-09-15 (aggressive, requires immediate start)
- **B:** Extend to 2026-10-15 (more realistic, buffer for DPO review)

**Recommendation:** Option B (account for legal review uncertainty)

---

### Decision 2: Operator Development
**Question:** Build operators in-house or use existing DevGuard operators?

**Options:**
- **A:** In-house development (full control, more work)
- **B:** Fork DevGuard operators (faster, less control)
- **C:** Hybrid (base on DevGuard, extend for ZKI)

**Recommendation:** Option C (best of both worlds)

---

### Decision 3: Service Expansion Priority
**Question:** Which services to deploy after the 5 production images?

**Options:**
- **A:** Learning Suite (moodle, ilias, nextcloud) - High user impact
- **B:** Infrastructure (argocd, monitoring) - Operational value
- **C:** Collaboration (element, etherpad) - Medium user impact

**Recommendation:** Option A (direct user value, aligns with Edu mission)

---

## 📞 Contact & Escalation

| Role | Name | Contact | Escalation Level |
|------|------|---------|------------------|
| Projektleitung | Tobias Weiß | tobias.weiss@hrz.uni-marburg.de | L3 |
| DevOps Engineer | TBD | TBD | L2 |
| Security Engineer | TBD | TBD | L2 |
| DPO | HRZ Datenschutz | datenschutz@hrz.uni-marburg.de | L3 |
| Justiziariat | Rechtsamt Marburg | rechtsamt@uni-marburg.de | L4 |

**Escalation Process:**
1. **L1:** Team channel (Slack/Matrix)
2. **L2:** Project lead (within 4h)
3. **L3:** Management (within 24h)
4. **L4:** External stakeholders (as needed)

---

## ✅ Checklist: Ready to Start?

- [x] Registry cleanup complete
- [x] Documentation updated
- [x] Implementation plans created
- [ ] GitLab PAT with read_registry scope
- [ ] DPO contact established
- [ ] Team briefed on priorities
- [ ] Test cluster ready
- [ ] Monitoring stack available
- [ ] Backup strategy defined

**If all boxes checked:** Proceed with Priority 1 implementation  
**If any box unchecked:** Address blockers before starting

---

**Last Updated:** 2026-08-07  
**Next Review:** 2026-08-14 (weekly status check)
