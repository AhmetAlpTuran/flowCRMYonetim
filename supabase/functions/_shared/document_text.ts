import { unzipSync } from "npm:fflate@0.8.2";

/** Text extraction and chunking for knowledge documents (knowledge-worker). */
export type DocumentFormat = "pdf" | "docx" | "xlsx" | "csv" | "txt" | "md";
export type Section = { heading: string | null; text: string };
export type ExtractedDocument = { sections: Section[]; pages: number | null };
export type Chunk = { heading: string | null; content: string };
export type DocumentErrorCode =
  | "unsupported_format"
  | "no_text"
  | "too_large"
  | "too_many_chunks"
  | "unreadable";

export class DocumentError extends Error {
  constructor(readonly code: DocumentErrorCode) {
    super(code);
  }
}

export const MAX_CHUNKS = 400;
export const CHUNK_CHARS = 1500;
const MAX_TEXT_CHARS = 600_000;
const MAX_UNZIPPED_BYTES = 60 * 1024 * 1024;
const MAX_PDF_PAGES = 300;
const MAX_TABLE_ROWS = 20_000;

export type PdfReader = (
  bytes: Uint8Array,
) => Promise<{ pages: string[] }>;

async function readPdf(bytes: Uint8Array): Promise<{ pages: string[] }> {
  const { extractText, getDocumentProxy } = await import("npm:unpdf@1.9.1");
  const pdf = await getDocumentProxy(new Uint8Array(bytes));
  if (pdf.numPages > MAX_PDF_PAGES) throw new DocumentError("too_large");
  const { text } = await extractText(pdf, { mergePages: false });
  return { pages: text };
}

export async function extractDocument(
  format: string,
  bytes: Uint8Array,
  pdf: PdfReader = readPdf,
): Promise<ExtractedDocument> {
  let result: ExtractedDocument;
  try {
    switch (format) {
      case "txt":
        result = { sections: [{ heading: null, text: decodeText(bytes) }], pages: null };
        break;
      case "md":
        result = { sections: markdownSections(decodeText(bytes)), pages: null };
        break;
      case "csv":
        result = {
          sections: [{ heading: null, text: tableText(parseCsv(decodeText(bytes))) }],
          pages: null,
        };
        break;
      case "docx":
        result = { sections: docxSections(bytes), pages: null };
        break;
      case "xlsx":
        result = { sections: xlsxSections(bytes), pages: null };
        break;
      case "pdf": {
        const { pages } = await pdf(bytes);
        if (pages.length > MAX_PDF_PAGES) throw new DocumentError("too_large");
        result = {
          sections: pages.map((text, index) => ({ heading: `Sayfa ${index + 1}`, text })),
          pages: pages.length,
        };
        break;
      }
      default:
        throw new DocumentError("unsupported_format");
    }
  } catch (error) {
    if (error instanceof DocumentError) throw error;
    throw new DocumentError("unreadable");
  }
  const total = result.sections.reduce((sum, section) => sum + section.text.length, 0);
  if (total > MAX_TEXT_CHARS) throw new DocumentError("too_large");
  return result;
}

/** UTF-8 (with or without BOM) or UTF-16 text; other bytes are read as Turkish Windows-1254. */
export function decodeText(bytes: Uint8Array): string {
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    return new TextDecoder("utf-8").decode(bytes.subarray(3));
  }
  if (bytes[0] === 0xff && bytes[1] === 0xfe) {
    return new TextDecoder("utf-16le").decode(bytes.subarray(2));
  }
  if (bytes[0] === 0xfe && bytes[1] === 0xff) {
    return new TextDecoder("utf-16be").decode(bytes.subarray(2));
  }
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return new TextDecoder("windows-1254").decode(bytes);
  }
}

export function normalizeText(text: string): string {
  return text
    .replace(/\r\n?/g, "\n")
    // deno-lint-ignore no-control-regex
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "")
    .replace(/[ \t ]+/g, " ")
    .split("\n").map((line) => line.trim()).join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function markdownSections(text: string): Section[] {
  const sections: Section[] = [];
  let heading: string | null = null;
  let lines: string[] = [];
  const flush = () => {
    if (lines.join("").trim()) sections.push({ heading, text: lines.join("\n") });
    lines = [];
  };
  for (const line of text.replace(/\r\n?/g, "\n").split("\n")) {
    const match = line.match(/^#{1,6}\s+(.+?)\s*#*\s*$/);
    if (match) {
      flush();
      heading = match[1].slice(0, 250);
    } else {
      lines.push(line);
    }
  }
  flush();
  return sections;
}

export function parseCsv(text: string): string[][] {
  const firstLine = text.split(/\r?\n/, 1)[0] ?? "";
  const counts = [",", ";", "\t"].map((d) => [d, firstLine.split(d).length] as const);
  const delimiter = counts.sort((a, b) => b[1] - a[1])[0][0];
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (quoted) {
      if (char === '"' && text[i + 1] === '"') {
        field += '"';
        i++;
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
    } else if (char === '"' && field === "") {
      quoted = true;
    } else if (char === delimiter) {
      row.push(field);
      field = "";
    } else if (char === "\n" || char === "\r") {
      if (char === "\r" && text[i + 1] === "\n") i++;
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
      if (rows.length > MAX_TABLE_ROWS) throw new DocumentError("too_large");
    } else {
      field += char;
    }
  }
  if (field !== "" || row.length) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}

/** Rows become "Header: value; ..." lines so each line stands on its own in a chunk. */
export function tableText(rows: string[][]): string {
  const cleaned = rows.map((row) => row.map((cell) => cell.replace(/\s+/g, " ").trim()))
    .filter((row) => row.some(Boolean));
  if (!cleaned.length) return "";
  const [header, ...body] = cleaned;
  if (!body.length) return header.filter(Boolean).join(" | ");
  return body.map((row) =>
    row.map((cell, index) => {
      if (!cell) return "";
      const name = header[index] || columnName(index);
      return `${name}: ${cell}`;
    }).filter(Boolean).join("; ")
  ).filter(Boolean).join("\n");
}

function columnName(index: number): string {
  let name = "";
  for (let n = index + 1; n > 0; n = Math.floor((n - 1) / 26)) {
    name = String.fromCharCode(65 + ((n - 1) % 26)) + name;
  }
  return name;
}

function unzip(bytes: Uint8Array, wanted: (name: string) => boolean): Record<string, string> {
  let total = 0;
  let files: Record<string, Uint8Array>;
  try {
    files = unzipSync(bytes, {
      filter: (file) => {
        if (!wanted(file.name)) return false;
        total += file.originalSize;
        if (total > MAX_UNZIPPED_BYTES) throw new DocumentError("too_large");
        return true;
      },
    });
  } catch (error) {
    if (error instanceof DocumentError) throw error;
    throw new DocumentError("unreadable");
  }
  const decoder = new TextDecoder("utf-8");
  return Object.fromEntries(
    Object.entries(files).map(([name, data]) => [name, decoder.decode(data)]),
  );
}

export function decodeXml(text: string): string {
  return text.replace(/&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);/g, (_, entity: string) => {
    if (entity[0] === "#") {
      const code = entity[1] === "x" ? parseInt(entity.slice(2), 16) : parseInt(entity.slice(1), 10);
      return Number.isFinite(code) && code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : "";
    }
    return { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" }[entity] ?? "";
  });
}

const HEADING_STYLE = /^(heading|balk|baslik|başlık|title|konubal)/i;

/** Word paragraphs and tables (cells joined with " | "); heading styles start sections. */
function docxSections(bytes: Uint8Array): Section[] {
  const xml = unzip(bytes, (name) => name === "word/document.xml")["word/document.xml"];
  if (xml === undefined) throw new DocumentError("unreadable");
  const sections: Section[] = [];
  let heading: string | null = null;
  let lines: string[] = [];
  let paragraph = "";
  let style = "";
  let tableDepth = 0;
  let cell: string[] = [];
  let row: string[] = [];
  const token =
    /<w:pStyle\b[^>]*w:val="([^"]*)"[^>]*\/>|<w:t(?:\s[^>]*)?>([^<]*)<\/w:t>|<w:tab\/>|<w:(?:br|cr)(?:\s[^>]*)?\/>|<\/w:p>|<w:tbl>|<\/w:tbl>|<\/w:tc>|<\/w:tr>/g;
  for (const match of xml.matchAll(token)) {
    const [whole, styleName, text] = match;
    if (styleName !== undefined) {
      style = styleName;
    } else if (text !== undefined) {
      paragraph += decodeXml(text);
    } else if (whole === "<w:tab/>") {
      paragraph += "\t";
    } else if (whole.startsWith("<w:br") || whole.startsWith("<w:cr")) {
      paragraph += "\n";
    } else if (whole === "</w:p>") {
      const value = paragraph.trim();
      if (tableDepth > 0) {
        if (value) cell.push(value);
      } else if (value && HEADING_STYLE.test(style)) {
        if (lines.join("").trim()) sections.push({ heading, text: lines.join("\n") });
        lines = [];
        heading = value.slice(0, 250);
      } else if (value) {
        lines.push(value);
      }
      paragraph = "";
      style = "";
    } else if (whole === "<w:tbl>") {
      tableDepth++;
    } else if (whole === "</w:tbl>") {
      tableDepth = Math.max(0, tableDepth - 1);
    } else if (whole === "</w:tc>") {
      row.push(cell.join(" "));
      cell = [];
    } else if (whole === "</w:tr>") {
      if (row.some(Boolean)) lines.push(row.join(" | "));
      row = [];
    }
  }
  if (lines.join("").trim()) sections.push({ heading, text: lines.join("\n") });
  return sections;
}

// Built-in Excel number formats that display dates or times.
const DATE_FORMAT_IDS = new Set([14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47]);

function attribute(tag: string, name: string): string | undefined {
  return tag.match(new RegExp(`\\b${name}="([^"]*)"`))?.[1];
}

function excelDate(serial: number, withTime: boolean): string {
  // Excel's day 0 is 1899-12-30 (including its 1900 leap-year quirk).
  const ms = Math.round((serial - 25569) * 86400000);
  const date = new Date(ms);
  if (!Number.isFinite(date.getTime())) return String(serial);
  const pad = (n: number) => String(n).padStart(2, "0");
  const day = `${pad(date.getUTCDate())}.${pad(date.getUTCMonth() + 1)}.${date.getUTCFullYear()}`;
  if (!withTime) return day;
  return `${day} ${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}`;
}

/** Every worksheet as a section of "Header: value" rows; date cells become dd.mm.yyyy. */
function xlsxSections(bytes: Uint8Array): Section[] {
  const files = unzip(bytes, (name) =>
    name === "xl/workbook.xml" || name === "xl/_rels/workbook.xml.rels" ||
    name === "xl/sharedStrings.xml" || name === "xl/styles.xml" ||
    /^xl\/worksheets\/[^/]+\.xml$/.test(name));
  const workbook = files["xl/workbook.xml"];
  if (workbook === undefined) throw new DocumentError("unreadable");
  const shared = [...(files["xl/sharedStrings.xml"] ?? "").matchAll(/<si>([\s\S]*?)<\/si>/g)]
    .map((match) =>
      [...match[1].matchAll(/<t(?:\s[^>]*)?>([^<]*)<\/t>/g)].map((t) => decodeXml(t[1])).join("")
    );
  const styles = files["xl/styles.xml"] ?? "";
  const customDates = new Set(
    [...styles.matchAll(/<numFmt\b[^>]*\/>/g)]
      .filter((m) => {
        const code = decodeXml(attribute(m[0], "formatCode") ?? "").replace(/"[^"]*"|\[[^\]]*\]/g, "");
        return /[dmy]/i.test(code) && !/^general$/i.test(code);
      })
      .map((m) => Number(attribute(m[0], "numFmtId"))),
  );
  const cellXfs = styles.match(/<cellXfs\b[^>]*>([\s\S]*?)<\/cellXfs>/)?.[1] ?? "";
  const dateStyles = [...cellXfs.matchAll(/<xf\b[^>]*\/?>/g)].map((m) => {
    const id = Number(attribute(m[0], "numFmtId") ?? "0");
    return DATE_FORMAT_IDS.has(id) || customDates.has(id);
  });
  const targets = new Map(
    [...(files["xl/_rels/workbook.xml.rels"] ?? "").matchAll(/<Relationship\b[^>]*\/>/g)]
      .map((m) => [attribute(m[0], "Id"), attribute(m[0], "Target")] as const),
  );
  const sections: Section[] = [];
  let rowCount = 0;
  for (const sheet of workbook.matchAll(/<sheet\b[^>]*\/>/g)) {
    const name = decodeXml(attribute(sheet[0], "name") ?? "");
    const target = targets.get(attribute(sheet[0], "r:id"));
    if (!target) continue;
    const path = target.startsWith("/") ? target.slice(1) : `xl/${target.replace(/^\.\//, "")}`;
    const xml = files[path];
    if (xml === undefined) continue;
    const rows: string[][] = [];
    for (const rowMatch of xml.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)) {
      if (++rowCount > MAX_TABLE_ROWS) throw new DocumentError("too_large");
      const cells: string[] = [];
      let next = 0;
      for (const cellMatch of rowMatch[1].matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
        const attrs = cellMatch[1];
        const inner = cellMatch[2] ?? "";
        const ref = attribute(attrs, "r");
        let column = next;
        if (ref) {
          const letters = ref.match(/^[A-Z]+/)?.[0] ?? "";
          column = [...letters].reduce((n, c) => n * 26 + c.charCodeAt(0) - 64, 0) - 1;
        }
        next = column + 1;
        const type = attribute(attrs, "t");
        const raw = inner.match(/<v>([^<]*)<\/v>/)?.[1];
        let value = "";
        if (type === "s") {
          value = shared[Number(raw)] ?? "";
        } else if (type === "inlineStr") {
          value = [...inner.matchAll(/<t(?:\s[^>]*)?>([^<]*)<\/t>/g)].map((t) => decodeXml(t[1])).join("");
        } else if (type === "b") {
          value = raw === "1" ? "Evet" : "Hayır";
        } else if (raw !== undefined) {
          value = decodeXml(raw);
          const number = Number(value);
          const style = Number(attribute(attrs, "s") ?? "0");
          if (type !== "str" && type !== "e" && Number.isFinite(number) && dateStyles[style]) {
            value = excelDate(number, number % 1 !== 0);
          }
        }
        if (column >= 0 && column < 200) cells[column] = value;
      }
      rows.push(Array.from(cells, (cell) => cell ?? ""));
    }
    const text = tableText(rows);
    if (text.trim()) sections.push({ heading: name ? `Sayfa: ${name}`.slice(0, 250) : null, text });
  }
  return sections;
}

function splitLong(unit: string, max: number): string[] {
  if (unit.length <= max) return [unit];
  const parts: string[] = [];
  let current = "";
  for (const sentence of unit.split(/(?<=[.!?…])\s+/)) {
    let piece = sentence;
    while (piece.length > max) {
      const cut = piece.lastIndexOf(" ", max);
      const at = cut > max / 2 ? cut : max;
      if (current) {
        parts.push(current);
        current = "";
      }
      parts.push(piece.slice(0, at).trim());
      piece = piece.slice(at).trim();
    }
    if (current && current.length + 1 + piece.length > max) {
      parts.push(current);
      current = piece;
    } else {
      current = current ? `${current} ${piece}` : piece;
    }
  }
  if (current) parts.push(current);
  return parts.filter(Boolean);
}

/** Packs lines into chunks of at most `max` characters, never across sections. */
export function chunkSections(sections: Section[], max = CHUNK_CHARS): Chunk[] {
  const chunks: Chunk[] = [];
  for (const section of sections) {
    const heading = section.heading?.trim().slice(0, 250) || null;
    const units = normalizeText(section.text).split("\n").filter(Boolean)
      .flatMap((line) => splitLong(line, max));
    let current = "";
    for (const unit of units) {
      if (current && current.length + 1 + unit.length > max) {
        chunks.push({ heading, content: current });
        current = unit;
      } else {
        current = current ? `${current}\n${unit}` : unit;
      }
      if (chunks.length > MAX_CHUNKS) throw new DocumentError("too_many_chunks");
    }
    if (current) chunks.push({ heading, content: current });
  }
  if (chunks.length > MAX_CHUNKS) throw new DocumentError("too_many_chunks");
  if (!chunks.length) throw new DocumentError("no_text");
  return chunks;
}
