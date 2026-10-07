# Thesis

Here you add your Thesis/Project report.

## 📂 Repository Structure

---

```bash
.
├─ appendix/appendix.tex        # All the content for the thesis appendix goes to here.
├─ bib/references.bib           # Here, you add all your citation sources.
├─ chapters/                    # Here, you will find multiple files. It's recommended to use the provided structure.
├─ figures/                     # Contains the figures used by the thesis.
├─ logo                         # Contains the ADS and TUD logos. You don't have to touch this folder.
├─ tables                       # Here, you add all your tables.
├─ abstract.tex                 # Here, you add all your abstract.
├─ acronyms.tex                 # Here, you add all your acronyms.
├─ header.tex                   # Here, you can add additional packages, new commands, or configuration changes.
├─ thesis.tex                   # This is the main file and entry point for compilation. Here, you can add or remove file inclusions.
├─ titlepage.tex                # Here, you can add the title of your thesis, your information, the supervisors, professors, and your subject (master's, diploma, bachelor's, or student thesis).
├─ TaskDescriptionSigned.pdf    # Signed task description. The student has to add this. Mandatory for Theses; Optional for Projects.
└─ TaskDescription.pdf          # Fallback PDF used if the artifact from the TaskDescription folder was not built successfully.
```

## 📦 Requirements

---

- PdfLaTeX
- texlive-science
- texlive-bibtex-extra
- biber

> Recommendation: Install [Tex Live](https://www.tug.org/texlive/quickinstall.html)

## 🧪 Test Environments

---

- TeXstudio 2.12.6, MiKTeX 2.9, Windows 10
- VSCode 1.104.2 + Extension: LaTeX Workshop 10.10.2; TeX 3.141592653; TeX Live 2024; Ubuntu 22.04 (6.5.0-45-generic)

## 🐞 Troubleshooting

---

### Use in Overleaf

- On the Overleaf site open `Menu` and set `Main document` to `thesis.tex`. 
- Make sure all the files and folders are in the root directory of the project, otherwise the list of acronyms is not shown (see [Stackoverflow](https://stackoverflow.com/questions/66924808/unable-to-show-the-glossary-with-printglossary-in-latex))

## 📝 Notes

---

- The student has to add a **TaskDescriptionSigned.pdf** for a thesis; for project work, this step is optional.
- Notice that the thesis.pdf is in the .gitignore. Please, **do not push the compiled pdf**.
- After every push, the pdf is **compiled on the CI**. You can see the result here: [Thesis](/../-/jobs/artifacts/main/file/thesis.pdf)
