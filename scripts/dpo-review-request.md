# DPO Review Request Template

## Email Template for DPO Review

**To:** datenschutz@hrz.uni-marburg.de  
**CC:** rechtsamt@uni-marburg.de  
**Subject:** Review Sicherheitsleitlinie openDesk Edu - ZKI-IT-Grundschutz Compliance

---

### Email Body

```
Sehr geehrte Damen und Herren,

wir bitten um rechtliches Review der Sicherheitsleitlinie für openDesk Edu,
einer hochschulischen Digital-Workplace-Plattform.

## Projektbeschreibung

openDesk Edu ist eine hochschulweite Digital-Workplace-Lösung, die folgende
Services bereitstellt:

- Groupware (E-Mail, Kalender, Kontakte) über SOGo
- Mailserver über Stalwart
- Dateifreigabe über openCloud
- Lernplattformen (Moodle, ILIAS, Nextcloud)
- Kollaborationstools (Element, Etherpad, Collabora)

Die Plattform wird auf dem HRZ K3s-Cluster der Universität Marburg betrieben
und folgt dem ZKI-IT-Grundschutz-Profil für Hochschulen.

## Rechtsgrundlagen

Die Sicherheitsleitlinie ist ausgerichtet auf:

1. **BSI IT-Grundschutz** (aktuelle Version 2026)
   - Basisschutz für Hochschulen
   - Komplementärbaukasten Cloud Computing
   - Komplementärbaukasten Container

2. **ZKI IT-Grundschutz-Profil für Hochschulen** (2025)
   - 111-Punkte-Compliance-Checkliste
   - Hochschulspezifische Anpassungen

3. **DSGVO**
   - Art. 32 (Sicherheit der Verarbeitung)
   - Art. 33 (Meldepflicht bei Verstößen)
   - Art. 34 (Benachrichtigung bei Verstößen)

4. **ISO/IEC 27001:2022**
   - Informationssicherheits-Managementsystem
   - Anhang A Kontrollen

## Inhalt der Sicherheitsleitlinie

Die Leitlinie (docs/SECURITY_POLICY.md) umfasst folgende Bereiche:

### 1. Sicherheitsprinzipien
- Defense in Depth
- Least Privilege
- Zero Trust
- Security by Design

### 2. Identitäts- und Zugriffsmanagement (IAM)
- Zentrale Authentifizierung via Keycloak
- SAML 2.0 / OIDC Support
- Multi-Faktor-Authentifizierung (MFA)
- RBAC mit 5 Rollenmodellen

### 3. Netzwerksicherheit
- Namespace-basierte Isolation
- Network Policies für alle Namespaces
- TLS 1.3 für alle externen Verbindungen
- mTLS für Service-to-Service (geplant)

### 4. Container-Sicherheit
- Image Signing mit Cosign
- Vulnerability Scanning vor Deployment
- SBOM-Generierung (SPDX, CycloneDX)
- Kyverno Policies für Enforcement
- Non-Root Container Enforcement

### 5. Datensicherheit
- Encryption in Transit (TLS)
- Encryption at Rest (Datenbanken)
- Secrets Management (Vault/Sealed Secrets)
- Backup-Strategie mit 90-Tage-Retention

### 6. Compliance & Audit
- ZKI-111-Punkte-Checkliste (aktuell 64% umgesetzt)
- Zentrale Log-Aggregation (Loki)
- 12 Monate Log-Retention
- Automatisierte Compliance-Scans

### 7. Notfallmanagement
- Incident Response Prozess (P0-P3)
- Disaster Recovery (RTO < 4h, RPO < 1h)
- Kyverno Policy Notfall-Abschaltverfahren
- Backup- und Restore-Prozeduren

### 8. Governance
- Policy Change Management
- Review-Zyklus (monatlich/quartalsweise/jährlich)
- Rollen & Verantwortlichkeiten

## Technische Umsetzung

Die Sicherheitsmaßnahmen werden durch folgende Technologien umgesetzt:

| Maßnahme | Technologie | Status |
|----------|-------------|--------|
| Authentifizierung | Keycloak | ✅ Implementiert |
| Netzwerksegmentierung | Kubernetes Network Policies | ✅ Implementiert |
| Container-Hardening | Kyverno Policies | ✅ Bereit für Deployment |
| Image-Signing | Cosign | ✅ Implementiert |
| Vulnerability Scanning | Grype, Trivy, Snyk | ✅ Implementiert |
| Log-Aggregation | Loki + Grafana | ⏳ Geplant |
| SIEM-Integration | Wazuh/Elastic | ⏳ Geplant |
| mTLS | Linkerd/Istio | ⏳ Geplant |

## Compliance Status

Aktueller Stand der ZKI-IT-Grundschutz-Umsetzung:

| Kategorie | Gesamt | Umgesetzt | Coverage |
|-----------|--------|-----------|----------|
| IAM & Authentifizierung | 15 | 9 | 60% |
| Netzwerksicherheit | 20 | 14 | 70% |
| Container-Sicherheit | 25 | 21 | 84% |
| Datensicherheit | 18 | 12 | 67% |
| Compliance & Audit | 15 | 8 | 53% |
| Notfallmanagement | 10 | 7 | 70% |
| **Gesamt** | **111** | **71** | **64%** |

Ziel ist es, bis Q4 2026 eine Compliance von 90%+ zu erreichen.

## Bitte um Review

Wir bitten um Review der Sicherheitsleitlinie bis zum **21. August 2026**.

Besondere Aufmerksamkeit bitten wir auf folgende Punkte zu legen:

1. **Datenschutzkonformität** der Datenverarbeitung
2. **Rechtliche Zulässigkeit** der Sicherheitsmaßnahmen
3. **DSGVO-Konformität** der Backup- und Logging-Strategien
4. **Haftungsfragen** bei Sicherheitsvorfällen

## Dokumentation

Die vollständige Sicherheitsleitlinie finden Sie im Anhang:
- docs/SECURITY_POLICY.md

Zusätzliche Dokumentation:
- IMPLEMENTATION-PLAN-PRIORITY-1.md (Umsetzungsplan)
- docs/POLICY-BACKUP.md (Backup-Strategie)
- k8s/security/ (Technische Implementierung)

## Kontakt

Für Rückfragen stehen wir gerne zur Verfügung:

**Projektleitung:**
- Tobias Weiß
- Email: tobias.weiss@hrz.uni-marburg.de
- Telefon: +49 6421 28-XXXX

**DevOps Team:**
- Email: devops@opendesk-edu.org

**Security Team:**
- Email: security@opendesk-edu.org

Vielen Dank für Ihre Unterstützung!

Mit freundlichen Grüßen

openDesk Edu Team
Universität Marburg
HRZ - Hochschulrechenzentrum
```

---

## Follow-Up Template (1 Week Before Deadline)

**To:** datenschutz@hrz.uni-marburg.de  
**Subject:** Follow-Up: Review Sicherheitsleitlinie openDesk Edu - Frist 21.08.2026

```
Sehr geehrte Damen und Herren,

wir möchten höflich an das Review der Sicherheitsleitlinie für openDesk Edu
erinnern. Die Frist für das Review endet am 21. August 2026.

Falls Sie Fragen haben oder weitere Informationen benötigen, stehen wir
gerne zur Verfügung.

Vielen Dank für Ihre Unterstützung!

Mit freundlichen Grüßen
openDesk Edu Team
```

---

## Response Handling

### If Approved

```
Vielen Dank für das positive Review!

Wir werden die Sicherheitsleitlinie wie folgt umsetzen:

1. Genehmigung dokumentieren
2. Leitlinie in Produktion überführen
3. Compliance-Monitoring aktivieren
4. Quartalsweise Reports erstellen

Für Rückfragen stehen wir gerne zur Verfügung.
```

### If Changes Requested

```
Vielen Dank für das Review und die Hinweise.

Wir werden folgende Änderungen vornehmen:

[List specific changes]

Die aktualisierte Version senden wir Ihnen bis zum [Datum] zur Freigabe.

Vielen Dank für Ihre Unterstützung!
```

### If Rejected

```
Vielen Dank für das detaillierte Review.

Wir werden folgende Punkte überarbeiten:

[List specific issues]

Bitte um ein Follow-Up Meeting zur Klärung der offenen Punkte.

Terminvorschläge:
- [Datum 1]
- [Datum 2]
- [Datum 3]

Vielen Dank für Ihre Unterstützung!
```

---

## Checklist for DPO Review

- [ ] Email sent to datenschutz@hrz.uni-marburg.de
- [ ] CC to rechtsamt@uni-marburg.de
- [ ] SECURITY_POLICY.md attached
- [ ] Implementation plan referenced
- [ ] Contact information provided
- [ ] Deadline communicated (21.08.2026)
- [ ] Follow-up scheduled (14.08.2026)
- [ ] Response documented
- [ ] Changes implemented (if requested)
- [ ] Final approval obtained

---

## Tracking

| Date | Action | Status | Notes |
|------|--------|--------|-------|
| 2026-08-07 | Initial Request Sent | ⏳ Pending | |
| 2026-08-14 | Follow-Up Scheduled | ⏳ Pending | |
| 2026-08-21 | Deadline | ⏳ Pending | |
| TBD | Review Received | ⏳ Pending | |
| TBD | Changes Implemented | ⏳ Pending | |
| TBD | Final Approval | ⏳ Pending | |

---

**Last Updated:** 2026-08-07
