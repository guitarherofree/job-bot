# Job Bot

A private macOS app for finding relevant roles, tailoring resumes and cover letters to each one, exploring adjacent career paths, and preparing application answers. Everything it writes comes from your own experience: it never invents qualifications, employers, dates, metrics or credentials, and it never uses em dashes.

Job Bot can't promise that any resume or application will get an interview. It helps you show the experience you have, clearly, for each posting.

## Install

**Option A: the ready-made app (no Terminal)**

1. Open the latest release on GitHub (Releases in the sidebar of this repository) and download `Job-Bot-<version>.zip`.
2. Double-click the zip and drag **Job Bot** into **Applications**.
3. The first time you open it, macOS may say it can't check the app for malicious software (it's signed for this Mac only, not by an Apple developer account). Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway** next to Job Bot. You only do this once.

**Option B: build from source** (needs Apple's Command Line Tools: `xcode-select --install`)

```bash
cd ~/Downloads/job-bot      # wherever you unzipped or cloned it
bash Scripts/install.sh
```

## Updates

Job Bot updates itself from this repository's GitHub Releases. Nothing to set up while the repository is public.

If the repository is ever made private again, Job Bot needs a read-only token once:

1. On GitHub: **Settings › Developer settings › Fine-grained tokens › Generate new token**. Repository access: only `job-bot`. Permissions: **Contents: Read-only**.
2. In Job Bot: **Privacy & Settings › Updates**, paste the token and click **Save** (it's stored in your Keychain).

Use **Job Bot › Check for Updates…** (or leave automatic checks on). Job Bot shows the version and release notes, downloads the app in the background, checks it's really Job Bot at that version, and installs it when you click **Restart to Install** or the next time you quit. If anything goes wrong, it tells you on the next launch and keeps the version you have.

### Publishing a release (for the maintainer)

1. Update `VERSION` and add `release-notes/<version>.md`.
2. Commit and push to `main`.
3. GitHub Actions builds and tests on a Mac, packages `Job-Bot-<version>.zip` (one app for Apple silicon and Intel), and, if that version hasn't been released yet, tags it and publishes the release with the app attached. If any test fails, nothing is published.

## How it works

**Master resume.** Import a PDF, Word (.docx) or text resume, or paste the text. Job Bot sorts it into contact details, summary and sections without adding anything, and tells you what it couldn't find. Edit, reorder, hide or remove anything. The master never changes when you tailor; save versions any time and compare or restore them from History.

**Jobs.** Add a job by link or by pasting the description. Job Bot reads the page the way a browser would, without signing in, and prefers the structured job data many career sites publish. It never downloads pages from sites that don't allow automated access (LinkedIn, Indeed, Handshake and similar); paste those descriptions instead. Each job shows the title, employer, location, source, original link, posting date when available, and date found, and flags likely duplicates and postings that appear closed.

**Compare.** Every responsibility and qualification is checked against your profile. You see the profile details that support each one, what's only partly supported, what isn't supported at all, and follow-up questions. If you have experience Job Bot doesn't know about, answer the question and save it to your profile notes: it then counts as evidence (notes are never printed).

**Tailored resume.** A copy of your master resume for the job, with suggestions: reorder bullets and skills, add a skill your experience already shows, use the posting's term for something you already say. Each suggestion explains why it may help and shows the posting lines and profile details behind it. Nothing changes until you accept it, and you can edit the wording first.

**Cover letter and answers.** Drafted only from your profile. Requirements without evidence are left out of the letter and listed for review. Application answers are marked "needs your confirmation", and personal questions (work authorization, pay, start date, demographics) are always left blank. Submitting is always up to you.

**Templates and export.** ATS Simple, Modern and Classic. All are single column with real text, so they read cleanly in applicant tracking systems and as plain text. Export to PDF, Word (.docx) or plain text, or copy as plain text.

**Find Jobs.** Search terms (starting with Assessment Specialist, ELA Content Developer and Item Writer), location filters (Remote, Atlanta and New York checked by default, an All option, and custom locations), job sites opened in your browser with your search terms, and 42 education companies with their careers pages. Prodigy, Edmentum, CommonLit and Seesaw publish public job-board feeds (Ashby, Greenhouse, Lever), so Job Bot can list their matching openings directly; for any other company with such a feed, "Find board" connects it.

**Pivot Paths.** Adjacent roles such as instructional design and curriculum design, with the profile evidence that supports each and the skills that may be missing; suggested search terms; and pay comparison against your current or target pay.

**Credentials.** Certifications, workshops and degree programs related to your pivot roles (or all of them), each with the reason it may help, time and cost from the source (estimates and unknowns are labeled) and a link.

**Examples.** Paste a resume you have permission to use and Job Bot keeps only general patterns (role titles, credentials, skills, how achievements are described). The text is discarded and nothing distinctive is stored.

## Privacy

- Your data lives in `~/Library/Application Support/Job Bot/` on your Mac (readable only by your account). A backup of the previous save is kept.
- API keys and the GitHub token are stored in the macOS Keychain, never in files or source code.
- Nothing is sent anywhere unless a service is on. **Privacy & Settings › What left this Mac** lists every request: when, where, why, and what was included.
- AI drafting is optional and off by default. When on, Job Bot sends your profile without your name or contact details, plus the job description, to Anthropic's API, and by default asks first, showing exactly what will be sent. Every AI draft is checked against your profile: drafts that cite no evidence are dropped, and numbers or names not found in your profile are flagged.
- Job Bot never uses your information to train models.
- **Export All Data** writes a folder with your library and plain-text copies of every document. **Delete All Data** removes everything, including Keychain items.

## Project layout

| Part | What it is |
| --- | --- |
| `Sources/JobBotCore` | Pure Swift (Foundation only): models, storage, resume and job parsing, matching with evidence, tailoring rules, cover letter and answer drafting, writing rules and fact checks, Word export, versions, discovery, pivots. |
| `Sources/JobBotRender` | macOS: paginated PDF output and resume file import. |
| `Sources/JobBotUI` | macOS: SwiftUI interface, app model, Keychain, AI client, job-page fetching, updater. |
| `Sources/JobBot` | The app entry point. |
| `Tests/` | Unit tests for the core, plus Mac tests that render every template, read the files back, and snapshot each screen. |
| `Scripts/` | Build, install and packaging scripts. |
| `.github/workflows/build.yml` | Builds and tests on a Mac for every push; publishes releases for `v*` tags. |

Data format note: files are JSON. New fields in later versions are optional so older libraries keep loading.
