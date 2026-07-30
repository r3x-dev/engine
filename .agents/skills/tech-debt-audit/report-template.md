# Tech Debt Audit Report

**Project**: {{PROJECT_NAME}}
**Date**: {{DATE}}
**Auditor**: Claude Code
**Directory**: {{DIRECTORY}}

---

## Executive Summary

{{SUMMARY - 2-3 sentences describing overall codebase health, major concerns, and key strengths}}

### Health Score: {{TOTAL}}/100

| Category | Score | Status |
|----------|-------|--------|
| Security | {{SECURITY_SCORE}}/20 | {{SECURITY_STATUS}} |
| Dependencies | {{DEPS_SCORE}}/20 | {{DEPS_STATUS}} |
| Complexity | {{COMPLEXITY_SCORE}}/20 | {{COMPLEXITY_STATUS}} |
| Coverage | {{COVERAGE_SCORE}}/20 | {{COVERAGE_STATUS}} |
| Maintainability | {{MAINTAIN_SCORE}}/20 | {{MAINTAIN_STATUS}} |

**Legend**: Pass | Warning | Fail

---

## Detailed Findings

### 1. Security Vulnerabilities

#### 1.1 Ruby Dependencies (bundler-audit)

| Severity | Count |
|----------|-------|
| Critical | {{CRITICAL}} |
| High | {{HIGH}} |
| Medium | {{MEDIUM}} |
| Low | {{LOW}} |

**Vulnerabilities Found:**

{{VULNERABILITY_LIST}}

#### 1.2 Static Analysis (Brakeman)

- **Total Warnings**: {{BRAKEMAN_TOTAL}}
- **High Confidence**: {{BRAKEMAN_HIGH}}
- **Medium Confidence**: {{BRAKEMAN_MEDIUM}}
- **Weak Confidence**: {{BRAKEMAN_WEAK}}

**Categories:**
{{BRAKEMAN_CATEGORIES}}

#### 1.3 Memory Leaks (bundler-leak)

- **Leaking Gems Found**: {{LEAK_COUNT}}

{{LEAK_LIST}}

#### 1.4 JavaScript Dependencies (npm/yarn audit)

| Severity | Count |
|----------|-------|
| Critical | {{JS_CRITICAL}} |
| High | {{JS_HIGH}} |
| Moderate | {{JS_MODERATE}} |
| Low | {{JS_LOW}} |

---

### 2. Dependency Freshness

#### 2.1 Ruby Dependencies

- **Total Gems**: {{TOTAL_GEMS}}
- **Outdated Gems**: {{OUTDATED_GEMS}} ({{OUTDATED_PERCENT}}%)
- **Libyears Behind**: {{LIBYEARS}} years

**Most Outdated:**

| Gem | Current | Latest | Years Behind |
|-----|---------|--------|--------------|
{{OUTDATED_GEM_TABLE}}

#### 2.2 JavaScript Dependencies

- **Total Packages**: {{TOTAL_PACKAGES}}
- **Outdated Packages**: {{OUTDATED_PACKAGES}}

---

### 3. Code Coverage

#### 3.1 Overall Coverage

- **Line Coverage**: {{LINE_COVERAGE}}%
- **Branch Coverage**: {{BRANCH_COVERAGE}}%

#### 3.2 Uncovered Critical Files

{{UNCOVERED_FILES_LIST}}

#### 3.3 Coverage by Directory

| Directory | Coverage |
|-----------|----------|
{{COVERAGE_BY_DIR_TABLE}}

---

### 4. Code Complexity

#### 4.1 RubyCritic Analysis

- **Average Complexity**: {{AVG_COMPLEXITY}}
- **Files Analyzed**: {{FILES_ANALYZED}}

#### 4.2 High-Risk Files (High Churn + High Complexity)

| File | Complexity | Churn | Rating |
|------|------------|-------|--------|
{{HIGH_RISK_FILES_TABLE}}

#### 4.3 Complexity Distribution

| Complexity Range | File Count | Percentage |
|------------------|------------|------------|
| 1-10 (Simple) | {{SIMPLE_COUNT}} | {{SIMPLE_PCT}}% |
| 11-20 (Moderate) | {{MOD_COUNT}} | {{MOD_PCT}}% |
| 21-50 (High) | {{HIGH_COUNT}} | {{HIGH_PCT}}% |
| 50+ (Very High) | {{VHIGH_COUNT}} | {{VHIGH_PCT}}% |

---

### 5. Skunk Score Analysis

#### 5.1 Summary

- **Total SkunkScore**: {{TOTAL_SKUNK}}
- **Average SkunkScore**: {{AVG_SKUNK}}
- **Files Analyzed**: {{SKUNK_FILES}}

#### 5.2 Top 10 Files by SkunkScore

| Rank | File | SkunkScore | Complexity | Coverage |
|------|------|------------|------------|----------|
{{TOP_SKUNK_TABLE}}

#### 5.3 Score Interpretation

- **0-25**: Good - Low risk, well-tested
- **25-50**: Moderate - May need attention
- **50-100**: High - Prioritize for refactoring
- **100+**: Critical - Immediate attention needed

---

### 6. Framework Health

#### 6.1 Version Information

| Component | Version | Status |
|-----------|---------|--------|
| Ruby | {{RUBY_VERSION}} | {{RUBY_STATUS}} |
| Rails | {{RAILS_VERSION}} | {{RAILS_STATUS}} |
| Bundler | {{BUNDLER_VERSION}} | {{BUNDLER_STATUS}} |
| Node.js | {{NODE_VERSION}} | {{NODE_STATUS}} |

#### 6.2 Code Statistics (rake stats)

| Name | Lines | LOC | Classes | Methods | M/C | LOC/M |
|------|-------|-----|---------|---------|-----|-------|
{{RAKE_STATS_TABLE}}

#### 6.3 Test Ratio

- **Code to Test Ratio**: 1:{{TEST_RATIO}}

---

### 7. Development Environment

#### 7.1 Setup Quality

| Item | Present | Notes |
|------|---------|-------|
| bin/setup | {{BIN_SETUP}} | {{BIN_SETUP_NOTES}} |
| docker-compose.yml | {{DOCKER}} | {{DOCKER_NOTES}} |
| README | {{README}} | {{README_NOTES}} |
| CI Configuration | {{CI}} | {{CI_NOTES}} |
| .env.example | {{ENV_EXAMPLE}} | {{ENV_NOTES}} |

---

## Recommendations

### Immediate Actions (Critical Priority)

{{CRITICAL_RECOMMENDATIONS}}

### Short-term Actions (High Priority)

{{HIGH_RECOMMENDATIONS}}

### Medium-term Actions (Normal Priority)

{{MEDIUM_RECOMMENDATIONS}}

### Long-term Actions (Low Priority)

{{LOW_RECOMMENDATIONS}}

---

## Metrics Baseline

Save these metrics to track improvement over time:

```yaml
audit_date: {{DATE}}
security:
  bundler_audit_vulnerabilities: {{TOTAL_VULNS}}
  brakeman_warnings: {{BRAKEMAN_TOTAL}}
  bundler_leak_issues: {{LEAK_COUNT}}
  npm_audit_vulnerabilities: {{JS_TOTAL_VULNS}}
dependencies:
  ruby_outdated_percent: {{OUTDATED_PERCENT}}
  ruby_libyears: {{LIBYEARS}}
  js_outdated_count: {{OUTDATED_PACKAGES}}
complexity:
  average_complexity: {{AVG_COMPLEXITY}}
  high_complexity_files: {{HIGH_COUNT}}
coverage:
  line_coverage: {{LINE_COVERAGE}}
  branch_coverage: {{BRANCH_COVERAGE}}
skunk:
  total_score: {{TOTAL_SKUNK}}
  average_score: {{AVG_SKUNK}}
health_score: {{TOTAL}}
```

---

## Appendix

### A. Tools Used

| Tool | Version | Purpose |
|------|---------|---------|
| bundler-audit | {{BA_VERSION}} | Ruby dependency vulnerabilities |
| brakeman | {{BRAKEMAN_VERSION}} | Rails static security analysis |
| bundler-leak | {{BL_VERSION}} | Memory leak detection |
| next_rails | {{NR_VERSION}} | Outdated dependency report |
| libyear-bundler | {{LB_VERSION}} | Dependency freshness metric |
| rubycritic | {{RC_VERSION}} | Code complexity analysis |
| skunk | {{SKUNK_VERSION}} | Combined tech debt metric |
| simplecov | {{SC_VERSION}} | Code coverage |

### B. Excluded from Analysis

{{EXCLUSIONS}}

### C. Known False Positives

{{FALSE_POSITIVES}}

### D. Notes

{{ADDITIONAL_NOTES}}

---

*Report generated by Claude Code Tech Debt Audit Skill*
*Reference: [FastRuby.io Blog](https://www.fastruby.io/blog)*
