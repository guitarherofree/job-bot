import Foundation

/// Fictional sample content for tests and previews. Not a real person or employer.
public enum SampleData {
    public static let resumeText = """
    JORDAN RIVERA
    Assessment Content Specialist
    Atlanta, GA | (404) 555-0142 | jordan.rivera@example.com | linkedin.com/in/jordan-rivera-example

    PROFESSIONAL SUMMARY
    Assessment content specialist with 9 years of experience in K–12 English Language Arts item development, standards alignment, and content quality review. Known for clear rubrics and reliable deadlines. Comfortable leading reviews with teachers and subject matter experts.

    EXPERIENCE
    Senior Content Developer | Northwind Assessment Services | Mar 2021 – Present
    • Write and review ELA items for grades 3–8 interim assessments, aligned to state standards
    • Lead bias and sensitivity reviews with panels of classroom teachers
    • Develop scoring rubrics and annotated anchor papers for constructed response items
    • Coordinate a team of 6 freelance item writers and track deliverables in Smartsheet

    Assessment Specialist
    Lakeside Learning Center, Decatur, GA    Aug 2016 – Feb 2021
    • Developed 1,200+ reading and writing items for formative assessments
    • Selected and edited reading passages for text complexity and grade-level fit
    • Performed quality assurance on item banks before each test administration
    • Trained new staff on the house style guide

    English Teacher
    Oak Hill Middle School, Atlanta, GA    2013 – 2016
    • Taught 7th and 8th grade English language arts to about 120 students each year
    • Designed unit assessments and common writing tasks with the grade-level team

    EDUCATION
    B.A., English, Georgia State University, 2013

    CERTIFICATIONS
    Georgia Educator Certificate, English 6–12

    SKILLS
    Item writing, Standards alignment, Rubric development, Passage selection, Quality assurance, Google Workspace, Smartsheet, QTI
    """

    public static let jobText = """
    ELA Assessment Content Developer
    Brightpath Learning
    Location: Remote (United States)

    About the role
    Brightpath Learning is hiring a content developer to build high-quality English Language Arts assessments for grades 3–8.

    Responsibilities
    • Write and revise item writing deliverables, including selected response and constructed response items aligned to state standards
    • Review items from contractors for accuracy, alignment, bias and sensitivity
    • Develop rubrics and scoring materials
    • Collaborate with psychometricians and product managers to meet test blueprints
    • Manage schedules for freelance writers

    Qualifications
    • Bachelor's degree in English, Education, or a related field
    • 5+ years of experience in K-12 assessment development
    • Experience with standards alignment and item writing for ELA
    • Strong knowledge of universal design for learning and accessibility guidelines
    • Familiarity with QTI or other item authoring platforms

    Preferred Qualifications
    • Classroom teaching experience
    • Experience with Articulate Storyline is a plus

    Compensation
    The pay range for this role is $68,000 - $82,000 per year.
    """

    public static var profile: Profile { ResumeParser.parse(resumeText).profile }

    public static func job(now: Date = Date()) -> Job {
        var j = JobParser.job(fromText: jobText, url: "https://careers.example.com/brightpath/ela-content-developer", source: "Pasted description", date: now)
        if j.employer.isEmpty { j.employer = "Brightpath Learning" }
        return j
    }
}
