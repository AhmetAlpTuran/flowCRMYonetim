# Knowledge documents and hybrid search (roadmap Phase 2f)

Businesses upload their own files (price lists, room rules, stock lists, FAQs) in the
app's **Bilgi bankası → Belgeler** section. The bot answers customer questions from those
documents as well as from the manual notes, using full-text and vector search together.

Migration: `supabase/migrations/20261108090000_knowledge_documents.sql`.

## Flow

1. The app uploads the file to the private `knowledge-documents` bucket at
   `{tenant}/{document}.{ext}`. The document ID is generated once and kept across retries,
   so an uncertain upload can be repeated without registering the file twice.
2. `register_knowledge_document(tenant, document, title, file_name)` (knowledge
   permission) checks the format, reads the size from Storage (at most 10 MB), enforces
   50 documents per business and queues the document. Clients cannot write
   `knowledge_documents` directly.
3. `knowledge-worker` (scheduled, `supabase/ops/schedule_knowledge_worker.sql`, secret
   `KNOWLEDGE_WORKER_SECRET`) claims one document per run with a fenced lease, downloads
   it and extracts its text (`_shared/document_text.ts`):
   - PDF through `unpdf` (one section per page, at most 300 pages; scanned PDFs fail
     with `no_text`).
   - Word `.docx`: paragraphs and tables. Heading styles start new sections.
   - Excel `.xlsx` and CSV: every row becomes `Header: value; ...`, so each line stands
     on its own. Date cells become `dd.mm.yyyy`.
   - TXT and Markdown: UTF-8, UTF-16 or Turkish Windows-1254. Markdown headings start
     new sections.
   The text is cut into passages of up to 1,500 characters, never across sections, with
   at most 400 passages per document. `finish_knowledge_document` stores the passages in
   `knowledge_chunks` and bumps the bot context version. Failures record a reason the app
   shows in Turkish (`unsupported_format`, `no_text`, `too_large`, `too_many_chunks`,
   `unreadable`, `file_missing`, `attempts_exhausted`). Transient errors retry up to 3 times.
4. The same worker embeds passages that have no embedding yet, with OpenAI
   `OPENAI_EMBEDDING_MODEL` (default `text-embedding-3-small`, 1536 dimensions). It sends
   up to 64 passages per run, grouped by business. Manual notes get one passage each
   (title + first 4,000 characters), kept in sync by a trigger; editing a note's text
   clears its embedding. Embedding tokens are recorded per business in
   `tenant_ai_usage.embedding_tokens`. They do not count against the chat token cap.
   `OPENAI_EMBEDDING_MODEL=off`, or no API key, disables embeddings, and search then
   uses full text only.

## Bot search

After `bot_reply_context`, the bot worker embeds the customer's message (8 s timeout)
and calls `bot_knowledge_search(job, lease, embedding, model, tokens)`. The search
combines two rankings by reciprocal rank fusion and returns at most five sources:

- **Full text** over manual notes and the passages of ready documents. Turkish letters
  are folded on both sides (`knowledge_fold`: "ücretli" and "ucretli" match). Words of
  six or more letters also match by a shortened prefix, a rough stand-in for Turkish
  suffixes ("otoparkınız" → `otopark:*`). Very short words and common filler are ignored.
- **Vector**: the 20 nearest passages of the same business and model by cosine distance
  (below 0.8), using an exact scan per business. An HNSW index can be added once
  businesses hold many thousands of passages.

If nothing matches, the latest notes are returned, then the opening passages of recent
documents. If the embedding call fails, the search runs on full text only; if the search
itself fails, the worker keeps `bot_reply_context`'s own notes. Document passages are
valid `knowledge_ids` in `complete_bot_reply` (same business only).

Changing `OPENAI_EMBEDDING_MODEL` makes old embeddings unused. Clear them so they are
embedded again: `update public.knowledge_chunks set embedding = null, embedding_model = null;`

## Deployment

Deploy `knowledge-worker`, set `KNOWLEDGE_WORKER_SECRET` (and optionally
`OPENAI_EMBEDDING_MODEL`), store the secret in Vault as `knowledge_worker_secret`, then
run `supabase/ops/schedule_knowledge_worker.sql` (every minute). On a hosted project,
check that one large PDF stays within the Edge Function CPU limit. If it does not, the
document fails after 3 attempts with `attempts_exhausted`.

## Verified

- Deno: `document_text_test.ts` (each format, Windows-1254, Excel dates, tables,
  headings, chunk limits, error codes, a real PDF through unpdf) and
  `knowledge_search_test.ts` (embedding request and validation, fallbacks).
- SQL: `knowledge_documents.sql` covers:
  - Storage and register permissions, size and format checks, idempotent register,
    tenant isolation, and the revoked direct writes.
  - Fenced claims, finishing a document with ready, failed or retry, and its passages.
  - The embedding queue and its backoff, and stale-hash saves.
  - Lexical, Turkish-folded and vector search, model filtering, and token recording.
  - Document passages as reply sources, and retry and delete.
- Live local run on the Edge runtime:
  - Real PDF, Word, Excel and CSV files were extracted into the expected passages, and
    a broken PDF failed with `unreadable`.
  - Search through PostgREST found the right document for Turkish questions, with and
    without Turkish letters.
  - Vector parameters and embedding saves worked through the REST API.
  - The bot worker ran with the new search.
  - A member's upload, register, list and delete worked through Storage and PostgREST.
- Runtime unverified: live OpenAI embedding calls (they need an API key) and the hosted
  Edge Function CPU limit for large PDFs.
