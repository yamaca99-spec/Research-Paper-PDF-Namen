#!/usr/bin/env python3
"""Creates small test PDFs (Tests/Fixtures/*.pdf) that imitate the first page of a paper.

Requires reportlab: pip install reportlab
The body text is placeholder text; only title/authors/identifiers matter for the tests.
"""
import os
import sys

from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

FILLER = (
    "This is placeholder body text used to test the renaming application. It mimics the "
    "layout of a scientific article so that the title detection has realistic input. "
)


def page(path, *, header=None, title_lines, authors, affiliations, extra=(), meta_title=None,
         meta_author=None):
    c = canvas.Canvas(path, pagesize=A4)
    width, height = A4
    if meta_title is not None:
        c.setTitle(meta_title)
    if meta_author is not None:
        c.setAuthor(meta_author)
    y = height - 50
    if header:
        c.setFont("Helvetica", 8)
        c.drawString(56, y, header)
        y -= 50
    c.setFont("Helvetica-Bold", 18)
    for line in title_lines:
        c.drawString(56, y, line)
        y -= 24
    y -= 8
    c.setFont("Helvetica", 11)
    c.drawString(56, y, authors)
    y -= 18
    c.setFont("Helvetica-Oblique", 8)
    for aff in affiliations:
        c.drawString(56, y, aff)
        y -= 12
    y -= 16
    c.setFont("Helvetica-Bold", 9.5)
    c.drawString(56, y, "Abstract")
    y -= 14
    c.setFont("Helvetica", 9.5)
    for line in extra:
        c.drawString(56, y, line)
        y -= 13
    words = (FILLER * 30).split()
    line = ""
    while y > 60 and words:
        word = words.pop(0)
        if c.stringWidth(line + " " + word, "Helvetica", 9.5) > width - 112:
            c.drawString(56, y, line.strip())
            y -= 13
            line = word
        else:
            line += " " + word
    c.showPage()
    c.save()


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)

    # Found online via the DOI printed on the page.
    page(
        os.path.join(out_dir, "scan_0001.pdf"),
        header="Review  |  https://doi.org/10.1038/nature14539",
        title_lines=["Deep learning"],
        authors="Yann LeCun1,2, Yoshua Bengio3 & Geoffrey Hinton4,5",
        affiliations=["1 Facebook AI Research, New York, USA", "3 Department of Computer Science, Montreal, Canada"],
    )

    # No identifier at all: must be found via the Crossref title search.
    page(
        os.path.join(out_dir, "download (3).pdf"),
        header="Article",
        title_lines=["Mastering the game of Go with deep neural", "networks and tree search"],
        authors="David Silver1*, Aja Huang1*, Chris J. Maddison1, Arthur Guez1, Laurent Sifre1",
        affiliations=["1 Google DeepMind, 5 New Street Square, London, UK"],
        meta_title="untitled",
    )

    # Fictional paper: nothing online, must be estimated from the PDF itself.
    page(
        os.path.join(out_dir, "draft_v3_final.pdf"),
        header="Journal of Imaginary Results 12 (2023) 1-10",
        title_lines=["A completely fictional study on automatically", "renaming scientific PDF files"],
        authors="Erika Mustermann1, Max Beispiel2",
        affiliations=["1 Department of Imaginary Science, University of Nowhere",
                      "2 Institute of Examples, Sample City"],
        extra=["© 2023 The Authors. Published by Imaginary Press."],
        meta_title="Microsoft Word - draft_v3.docx",
        meta_author="Erika Mustermann; Max Beispiel",
    )
    print("wrote test PDFs to", out_dir)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "Tests", "Fixtures"))
