# RLS GitHub Showcase acceptance

- Status: **PASS**
- Expected terminal state: `RLS_GITHUB_SHOWCASE_COMPLETE_WITH_VIVADO_COMPARISON_PENDING`
- Checks: 23; failures: 0
- DOCX/PDF visual QA: Word COM + Poppler, 4/4 pages inspected
- SVG visual QA: 6/6 browser renders inspected

| Check | Status | Detail |
| --- | --- | --- |
| required_files | PASS | core files present |
| bilingual_topics | PASS | 16/16 present |
| bilingual_facts | PASS | quantitative facts aligned |
| claim_boundaries | PASS | boundaries explicit |
| no_fake_badges | PASS | no unsupported badge |
| public_results_schema | PASS | domain,metric,variant,value,unit,status,tool,evidence_file,claim_boundary |
| not_available_not_zero | PASS | NOT_AVAILABLE is textual |
| public_evidence_paths | PASS | all evidence paths resolve |
| convergence_metrics | PASS | 43.166/43.249 dB and 684/689 |
| convergence_curve | PASS | 1,000 deterministic rows |
| svg_assets | PASS | 6/6 nontrivial |
| svg_xml | PASS | all parse |
| svg_determinism | PASS | byte-identical regeneration |
| docx_fingerprint_metadata | PASS | fingerprint present; creator/rsid/custom clean |
| docx_compact_preset | PASS | Letter/1in/Calibri+YaHei/styles/fixed tables/no title rule |
| pdf_fingerprint_metadata | PASS | 4 Letter pages; metadata scrubbed |
| document_fingerprint_table | PASS | MD/DOCX/PDF hashes current |
| rtl_filelists | PASS | relative, existing, XCI-free |
| utf8_text | PASS | all public text decodes |
| markdown_links | PASS | none broken |
| powershell_syntax | PASS | all parse |
| security_audits | PASS | 3/3 PASS |
| repository_manifest | PASS | entries=145 |
