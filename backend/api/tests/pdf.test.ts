import { describe, expect, it } from "vitest";
import { extractText } from "../src/services/file-text";

function tinyPdf(text: string): Uint8Array {
  const objs = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 100] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    `<< /Length ${`BT /F1 12 Tf 10 50 Td (${text}) Tj ET`.length} >>\nstream\nBT /F1 12 Tf 10 50 Td (${text}) Tj ET\nendstream`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  ];
  let out = "%PDF-1.4\n";
  const offs: number[] = [];
  objs.forEach((o, i) => {
    offs.push(out.length);
    out += `${i + 1} 0 obj\n${o}\nendobj\n`;
  });
  const xref = out.length;
  out += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${offs.map((o) => `${String(o).padStart(10, "0")} 00000 n \n`).join("")}`;
  out += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return new TextEncoder().encode(out);
}

describe("file text extraction", () => {
  it("reads text files and PDFs", async () => {
    const meta = (name: string, kind: "text" | "pdf") => ({ id: "x", name, mime: "", size: 1, kind, createdAt: 0 });
    expect((await extractText(meta("a.csv", "text"), new TextEncoder().encode("a,b"))).text).toBe("a,b");
    const pdf = await extractText(meta("a.pdf", "pdf"), tinyPdf("Bench 3x5 at 60"));
    expect(pdf.text ?? pdf.note).toContain("Bench 3x5 at 60");
  });
});
