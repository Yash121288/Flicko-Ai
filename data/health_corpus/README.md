# Flicko Health Corpus

This folder is the ingestion target for Flicko's Disha-like health knowledge layer.

Do not place private user health records here. User memory/outcomes stay in database tables tied to consented app users.

## Buckets

- `source_registry/*.jsonl`: public or authorized source metadata.
- `raw_sources/`: archived public PDFs/pages if license allows local storage.
- `normalized_chunks/*.jsonl`: normalized source text chunks linked to source URLs.
- `protocols/*.jsonl`: structured protocol records linked to chunks/evidence.
- `food_rules/*.jsonl`: condition-specific food rules and Indian substitutions.
- `safety_rules/*.jsonl`: red-flag and escalation rules.
- `flows/*.jsonl`: intake question flows.
- `reminders/*.jsonl`: proactive call/chat/push scripts.
- `reports/*.jsonl`: reusable report markdown blocks.
- `metrics/*.jsonl`: dashboard and outcome metric definitions.
- `memory_schemas/*.jsonl`: schemas for extracting memory from chat/call.
- `eval_sets/`: test cases and synthetic scenarios.
- `vector_index/`: embeddings/vector index output.

## Import

```powershell
cd apps\backend
python manage.py import_health_corpus
```

Use `--dry-run` to validate files without committing writes.
