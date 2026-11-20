import Foundation

/// Vocabulary for spotting skills and tools in postings and resumes. It leans toward education,
/// assessment and content work, but general professional terms are included too.
public enum Lexicon {
    public static let skillPhrases: [String] = [
        // Assessment and content
        "item writing", "item development", "item review", "item analysis", "item bank", "item banking", "test development",
        "assessment development", "assessment design", "test design", "test blueprint", "blueprint", "standards alignment",
        "alignment", "psychometrics", "standard setting", "rubric development", "rubrics", "scoring", "rangefinding",
        "performance tasks", "constructed response", "selected response", "multiple choice", "technology-enhanced items",
        "passage selection", "passage writing", "reading passages", "text complexity", "lexile", "depth of knowledge", "dok",
        "bloom's taxonomy", "universal design for learning", "bias and sensitivity", "fairness review", "accessibility",
        "accommodations", "content review", "content development", "content quality assurance", "quality assurance",
        "fact checking", "copyediting", "proofreading", "editing", "style guide", "permissions", "copyright clearance",
        "formative assessment", "summative assessment", "interim assessment", "benchmark assessment", "state assessment",
        "english language arts", "reading", "writing", "literacy", "phonics", "foundational skills", "vocabulary",
        "grammar", "language conventions", "speaking and listening", "argument writing", "informational text", "literature",
        "math", "mathematics", "science", "social studies", "k-12", "elementary", "middle school", "high school",
        "common core state standards", "state standards", "ccss", "ngss", "teks", "best standards",
        // Learning design
        "instructional design", "curriculum development", "curriculum design", "lesson planning", "unit planning",
        "scope and sequence", "learning objectives", "learning outcomes", "backward design", "addie", "sam model",
        "storyboarding", "e-learning", "elearning", "blended learning", "adult learning", "andragogy",
        "learning experience design", "differentiated instruction", "differentiation", "scaffolding",
        "english learners", "special education", "social-emotional learning", "professional development", "teacher training",
        "facilitation", "coaching", "classroom instruction", "teaching",
        // Tools and formats
        "qti", "scorm", "xapi", "lms", "learning management system", "canvas", "schoology", "blackboard", "moodle",
        "google classroom", "articulate storyline", "articulate rise", "articulate 360", "adobe captivate", "camtasia",
        "vyond", "h5p", "figma", "canva", "adobe creative cloud", "adobe indesign", "indesign", "photoshop", "illustrator",
        "microsoft office", "microsoft word", "microsoft excel", "excel", "powerpoint", "google workspace", "google docs",
        "google sheets", "smartsheet", "jira", "confluence", "asana", "trello", "monday.com", "airtable", "notion",
        "salesforce", "tableau", "sql", "python", "html", "css", "wordpress", "xml", "markdown", "wcag", "section 508",
        "alt text", "screen readers", "chatgpt", "generative ai", "ai tools", "prompt engineering", "claude",
        // Ways of working
        "project management", "stakeholder management", "vendor management", "cross-functional collaboration",
        "collaboration", "communication", "written communication", "attention to detail", "time management",
        "deadline-driven", "remote work", "mentoring", "training", "leadership", "team leadership", "process improvement",
        "data analysis", "research", "user research", "usability testing", "product management", "agile", "scrum",
        "subject matter expert", "sme review", "client management", "customer service", "budgeting", "reporting",
    ]

    /// Lowercased phrases → canonical form.
    public static let skillSet: Set<String> = Set(skillPhrases.map { TextTools.words($0).joined(separator: " ") })

    /// Skill phrases found in the text, in the canonical lowercase form.
    public static func skills(in text: String) -> [String] {
        let hay = " " + TextTools.words(text).joined(separator: " ") + " "
        var found: [String] = []
        for phrase in skillSet where hay.contains(" " + phrase + " ") {
            found.append(phrase)
        }
        // Drop phrases contained in a longer phrase that was also found ("assessment" inside "assessment design").
        return found.filter { short in !found.contains { $0 != short && $0.contains(short) } }.sorted()
    }

    public static let actionVerbs: Set<String> = [
        "achieved", "adapted", "administered", "advised", "aligned", "analyzed", "applied", "assessed", "assisted", "audited",
        "authored", "built", "calibrated", "championed", "coached", "collaborated", "compiled", "completed", "composed",
        "conducted", "consulted", "contributed", "coordinated", "created", "curated", "customized", "defined", "delivered",
        "designed", "developed", "devised", "directed", "documented", "drafted", "drove", "edited", "educated", "enhanced",
        "established", "evaluated", "executed", "expanded", "facilitated", "finalized", "formatted", "guided", "helped",
        "identified", "implemented", "improved", "increased", "initiated", "instructed", "integrated", "introduced",
        "launched", "led", "maintained", "managed", "mapped", "mentored", "modernized", "monitored", "negotiated",
        "onboarded", "optimized", "orchestrated", "organized", "oversaw", "partnered", "piloted", "planned", "prepared",
        "presented", "prioritized", "produced", "programmed", "proofread", "proposed", "published", "recommended",
        "reduced", "refined", "researched", "resolved", "restructured", "reviewed", "revised", "scored", "selected",
        "served", "simplified", "spearheaded", "standardized", "streamlined", "strengthened", "structured", "supervised",
        "supported", "taught", "tested", "trained", "translated", "tutored", "updated", "validated", "verified", "wrote",
        // present tense forms used in current roles
        "adapt", "advise", "align", "analyze", "assess", "author", "build", "calibrate", "coach", "collaborate", "conduct",
        "consult", "contribute", "coordinate", "create", "curate", "design", "develop", "direct", "draft", "edit",
        "evaluate", "facilitate", "guide", "implement", "lead", "maintain", "manage", "mentor", "monitor", "oversee",
        "partner", "plan", "prepare", "present", "produce", "proofread", "research", "review", "revise", "score",
        "select", "serve", "supervise", "support", "teach", "test", "train", "update", "validate", "verify", "write",
        "ensure", "provide", "deliver", "work", "help", "apply", "identify", "establish", "track", "audit", "own",
    ]

    /// Imperative verbs that usually start a responsibility in a posting.
    public static let responsibilityVerbs: Set<String> = [
        "write", "develop", "review", "create", "design", "lead", "manage", "collaborate", "partner", "ensure", "edit",
        "evaluate", "analyze", "build", "coordinate", "support", "maintain", "conduct", "provide", "deliver", "draft",
        "revise", "align", "facilitate", "oversee", "plan", "research", "train", "mentor", "communicate", "work", "serve",
        "contribute", "apply", "identify", "establish", "track", "prepare", "participate", "assist", "monitor", "own",
        "drive", "author", "produce", "proofread", "score", "test", "validate", "verify", "curate", "select", "help",
        "implement", "organize", "present", "respond", "update", "use", "engage", "advise", "consult", "guide",
    ]
}
