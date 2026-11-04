import { assert, assertEquals, assertRejects, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { strToU8, zipSync } from "npm:fflate@0.8.2";
import {
  chunkSections,
  decodeText,
  DocumentError,
  extractDocument,
  parseCsv,
  tableText,
} from "./document_text.ts";

function minimalPdf(lines: string[]): Uint8Array {
  const esc = (s: string) => s.replace(/[\\()]/g, (c) => "\\" + c);
  const stream = "BT /F1 12 Tf 72 720 Td " +
    lines.map((l, i) => (i ? "0 -16 Td " : "") + `(${esc(l)}) Tj`).join(" ") + " ET";
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
  ];
  let out = "%PDF-1.4\n";
  const offsets: number[] = [];
  objects.forEach((o, i) => {
    offsets.push(out.length);
    out += `${i + 1} 0 obj\n${o}\nendobj\n`;
  });
  const xref = out.length;
  out += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n` +
    offsets.map((o) => String(o).padStart(10, "0") + " 00000 n \n").join("");
  out += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return new TextEncoder().encode(out);
}

Deno.test("text files decode UTF-8, BOMs and Turkish Windows-1254", () => {
  assertEquals(decodeText(new Uint8Array([0xef, 0xbb, 0xbf, ...strToU8("Çay ücretsiz")])), "Çay ücretsiz");
  // "ğüşıöç" in Windows-1254 is not valid UTF-8.
  assertEquals(decodeText(new Uint8Array([0xf0, 0xfc, 0xfe, 0xfd, 0xf6, 0xe7])), "ğüşıöç");
  assertEquals(decodeText(new Uint8Array([0xff, 0xfe, 0x41, 0x00, 0x1f, 0x01])), "Ağ");
});

Deno.test("CSV rows become self-contained header: value lines", () => {
  const rows = parseCsv('Marka;Model;Fiyat\n"Fiat";"Egea; 1.4";"450.000"\r\nRenault;"Clio ""Joy""";\n');
  assertEquals(rows[1], ["Fiat", "Egea; 1.4", "450.000"]);
  assertEquals(
    tableText(rows),
    "Marka: Fiat; Model: Egea; 1.4; Fiyat: 450.000\nMarka: Renault; Model: Clio \"Joy\"",
  );
  assertEquals(tableText(parseCsv("a,b\n")), "a | b");
});

Deno.test("Word documents keep paragraphs, tables and heading sections", async () => {
  const xml = `<?xml version="1.0"?><w:document><w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Oda Kuralları</w:t></w:r></w:p>
    <w:p><w:r><w:t xml:space="preserve">Giriş 14:00, </w:t></w:r><w:r><w:t>çıkış 11:00 &amp; sessizlik 23:00.</w:t></w:r></w:p>
    <w:p><w:r><w:delText>silinmiş</w:delText><w:instrText>PAGE</w:instrText></w:r></w:p>
    <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Oda</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Fiyat</w:t></w:r></w:p></w:tc></w:tr>
    <w:tr><w:tc><w:p><w:r><w:t>Deniz</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>2.500 TL</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
    <w:p><w:pPr><w:pStyle w:val="Balk2"/></w:pPr><w:r><w:t>İptal</w:t></w:r></w:p>
    <w:p><w:r><w:t>3 gün öncesine kadar ücretsiz.</w:t></w:r></w:p>
  </w:body></w:document>`;
  const doc = await extractDocument("docx", zipSync({ "word/document.xml": strToU8(xml) }));
  assertEquals(doc.sections, [
    { heading: "Oda Kuralları", text: "Giriş 14:00, çıkış 11:00 & sessizlik 23:00.\nOda | Fiyat\nDeniz | 2.500 TL" },
    { heading: "İptal", text: "3 gün öncesine kadar ücretsiz." },
  ]);
});

Deno.test("Excel sheets use headers, shared strings and date formats", async () => {
  const files = {
    "xl/workbook.xml": strToU8(
      `<workbook><sheets><sheet name="Stok &amp; Fiyat" sheetId="1" r:id="rId1"/></sheets></workbook>`,
    ),
    "xl/_rels/workbook.xml.rels": strToU8(
      `<Relationships><Relationship Id="rId1" Type="x" Target="worksheets/sheet1.xml"/></Relationships>`,
    ),
    "xl/sharedStrings.xml": strToU8(
      `<sst><si><t>Araç</t></si><si><t>Gelis</t></si><si><r><t>Fiat </t></r><r><t>Egea</t></r></si></sst>`,
    ),
    "xl/styles.xml": strToU8(
      `<styleSheet><numFmts><numFmt numFmtId="164" formatCode="dd/mm/yyyy;@"/></numFmts>
       <cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/></cellXfs></styleSheet>`,
    ),
    "xl/worksheets/sheet1.xml": strToU8(`<worksheet><sheetData>
      <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="inlineStr"><is><t>Hasarsız</t></is></c><c r="D1" t="inlineStr"><is><t>Km</t></is></c></row>
      <row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2" s="1"><v>45984</v></c><c r="C2" t="b"><v>1</v></c><c r="D2"><v>42000</v></c></row>
      <row r="3"><c r="A3" t="str"><v>Clio</v></c><c r="B3" s="2"><v>45985.5</v></c><c r="D3"><v>15000</v></c></row>
    </sheetData></worksheet>`),
  };
  const doc = await extractDocument("xlsx", zipSync(files));
  assertEquals(doc.sections, [{
    heading: "Sayfa: Stok & Fiyat",
    text: "Araç: Fiat Egea; Gelis: 23.11.2025; Hasarsız: Evet; Km: 42000\n" +
      "Araç: Clio; Gelis: 24.11.2025 12:00; Km: 15000",
  }]);
});

Deno.test("PDF pages become sections through unpdf", async () => {
  const doc = await extractDocument("pdf", minimalPdf(["Kahvalti 08:00-10:30", "Check-in 14:00"]));
  assertEquals(doc.pages, 1);
  assertEquals(doc.sections, [{ heading: "Sayfa 1", text: "Kahvalti 08:00-10:30\nCheck-in 14:00" }]);
  // A reader may also be injected (scanned PDFs yield no text).
  const scanned = await extractDocument("pdf", new Uint8Array([1]), async () => ({ pages: ["", " "] }));
  assertThrows(() => chunkSections(scanned.sections), DocumentError, "no_text");
});

Deno.test("Markdown headings split sections; bad input maps to error codes", async () => {
  const md = await extractDocument("md", strToU8("Giriş\n# Ulaşım\nHavalimanı 20 dk\n## Otopark ##\nÜcretsiz"));
  assertEquals(md.sections, [
    { heading: null, text: "Giriş" },
    { heading: "Ulaşım", text: "Havalimanı 20 dk" },
    { heading: "Otopark", text: "Ücretsiz" },
  ]);
  await assertRejects(() => extractDocument("exe", new Uint8Array([1])), DocumentError, "unsupported_format");
  await assertRejects(() => extractDocument("docx", strToU8("not a zip")), DocumentError, "unreadable");
  await assertRejects(
    () => extractDocument("txt", strToU8("x".repeat(600_001))),
    DocumentError,
    "too_large",
  );
});

Deno.test("chunks pack lines up to the limit, split long text and never cross sections", () => {
  const long = "Bu bir cümle. ".repeat(40).trim(); // 559 characters
  const chunks = chunkSections([
    { heading: "Sayfa 1", text: `Satır bir\n\n\nSatır   iki\n${long}` },
    { heading: null, text: "Ayrı bölüm" },
  ], 200);
  assert(chunks.every((c) => c.content.length <= 200));
  assertEquals(chunks[0], { heading: "Sayfa 1", content: "Satır bir\nSatır iki" });
  assert(chunks.slice(1, -1).every((c) => c.heading === "Sayfa 1"));
  assertEquals(chunks.slice(1, -1).map((c) => c.content).join(" "), long);
  assertEquals(chunks.at(-1), { heading: null, content: "Ayrı bölüm" });
  assertThrows(() => chunkSections([{ heading: null, text: " \n " }]), DocumentError, "no_text");
  assertThrows(
    () => chunkSections([{ heading: null, text: "x\n".repeat(401) }], 1),
    DocumentError,
    "too_many_chunks",
  );
});
