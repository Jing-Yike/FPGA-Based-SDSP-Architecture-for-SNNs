# LaTeX Task Template

Author: Matthias Nickel \
E-Mail: Matthias.Nickel@tu-dresden.de \
Kudos to [Julian Haase](mailto:Julian.Haase@tu-dresden.de) for creating the original template as well as to [Paul Gottschaldt](mailto:paul.gottschaldt@tu-dresden.de) and [Lester Kalms](mailto:lester.kalms@tu-dresden.de) for their support. \
Date: 05.11.2025 \
Please contact the author in case of questions.

## 📂 Repository Structure

---

```bash
.
├─ TaskDescription.tex    # This is the main file to be compiled. This is the only file you need to work with.
├─ tudscrreprt.cls        # The TUD style file contains the latest links to the new collaborative design logos, which can be found in the logo folder.
└─ logo/                  # Here, you will find the ADS logo, as well as the new logos designed in cooperation with TUD.

```

## 📦 Requirements

---

- PdfLaTeX
- Tested with 
  - TeXstudio 2.12.6, MiKTeX 2.9, Windows 10
  - VSCode 1.104.2 + Extension: LaTeX Workshop 10.10.2; TeX 3.141592653; TeX Live 2024; Ubuntu 22.04 (6.5.0-45-generic)
- Other version not tested

## 🔧 Task Description Parameters

---

You can adapt the following parameters in **TaskDescription.tex** to your needs.

| Lines     | Description                           | Comment                                                                                                                                                                                                   |
|-----------|---------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 11        | Used Language                         | Add 'english' or 'ngerman' in the \documentclass, e.g. `\documentclass[english, 10pt]{tudscrreprt}`                                                                                                       |
| 25 - 27   | Watermark for drafts.                 | Comment out or remove those lines for the final version                                                                                                                                                   |
| 49        | ADS logo                              | Comment out or remove this line to remove the ADS logo                                                                                                                                                    |
| 61 - 63   | Title of the thesis/paper.            | -                                                                                                                                                                                                         |
| 64        | Type of thesis/paper                  | Use the following keywords: <br> **Thesis:** master, diploma, bachelor or student<br> **Großer Beleg:** evidence <br> **Project:** project <br> **Seminar:** seminar <br> **Internship:** internship |
| 66        | First and last name                   | -                                                                                                                                                                                                         |
| 67        | Matriculation number                  | -                                                                                                                                                                                                         |
| 68        | Module                                | Module ID, e.g. INF-PM-ANW <br> Comment out or remove this line for thesis; Used for projects and seminars                                                                                               |
| 69        | Course                                | Course of study, e.g. Master Computer Science, Master NES                                                                                                                                                 |
| 71        | Matriculation year of the student.    | -                                                                                                                                                                                                         |
| 72        | Start date of thesis.                 | -                                                                                                                                                                                                         |
| 73        | Submisson date of thesis.             | This is not the date of the final presentation.                                                                                                                                                           |
| 74        | List of Supervisors                   | You can declare multiple supervisors by adding `\and` between them.                                                                                                                                       |
| 75        | Referees/Reviewer of the thesis       | You can declare multiple referees by adding `\and` between them. Put Diana as first referee.                                                                                                              |
| 76        | Professor                             | You can leave the line as it is with Diana as professor.                                                                                                                                                  |
| 77 - 78   | The chairmans depending on the course | For Computer Science you don't need this line. <br> Uncomment the following line depending on the course of study <br> **NES:** 77 (Mikolajick) <br> **IST:** 78 (Wollschlaeger)                       |
| 79 - ...  | Task description and focus            | In the first field, provide a task description in text form. In the second field, provide a list of bullet points containing the tasks to be fulfilled.                                                   |

> Note: Look at the comments in the tex-file for more details.

## 🧑‍💻 Development Notes

---

- Changed the German and English locations for the `\discipline` command to "Module" and "Module," respectively. See the definitions for `\disciplinename` in the `tudscrreprt.cls` file.
- Added a `\module` wrapper for the `\discipline` command in the TaskDescription.tex file (see line 38).
