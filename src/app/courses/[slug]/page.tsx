import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getCatalogCourseBySlug } from "@/lib/catalog-data";

type CoursePageProps = {
  params: Promise<{ slug: string }>;
};

export async function generateMetadata({ params }: CoursePageProps): Promise<Metadata> {
  const { slug } = await params;
  const result = await getCatalogCourseBySlug(slug);

  if (result.kind === "found") {
    return { title: result.course.title, description: result.course.subtitle };
  }
  if (result.kind === "error") {
    return { title: "Course temporarily unavailable" };
  }
  return { title: "Course not found" };
}

export default async function CourseDetailPage({ params }: CoursePageProps) {
  const { slug } = await params;
  const result = await getCatalogCourseBySlug(slug);

  if (result.kind === "not-found") notFound();
  if (result.kind === "error") {
    return (
      <main id="main-content" className="course-detail">
        <div className="page-shell">
          <div className="empty-state" role="alert">
            <h1>Course details are temporarily unavailable.</h1>
            <p>We couldn’t load this course right now. Please try again later.</p>
            <Link className="button-solid" href="/courses">Return to courses</Link>
          </div>
        </div>
      </main>
    );
  }

  const { course } = result;
  const isDemo = course.source === "demo";

  return (
    <main id="main-content" className="course-detail">
      <div className="page-shell">
        <p className="breadcrumbs">
          <Link href="/courses">{isDemo ? "Sample courses" : "Courses"}</Link>
          <span aria-hidden="true"> / </span>{course.title}
        </p>
        <div className="detail-layout">
          <article className="detail-main">
            <span className="sample-tag">{isDemo ? "Demo content · no enrollment" : "Published course"}</span>
            <p className="eyebrow" style={{ marginTop: "1.2rem" }}>{course.category} · {course.level}</p>
            <h1 className="detail-title">{course.title}</h1>
            {course.subtitle ? <p className="section-copy">{course.subtitle}</p> : null}
            <p className="detail-description">{course.description}</p>
            <p className="course-instructor">{isDemo ? "Sample instructor" : "Instructor"} · {course.instructorName}</p>

            {course.outcomes.length > 0 ? (
              <section className="detail-section" aria-labelledby="outcomes-heading">
                <h2 id="outcomes-heading">{isDemo ? "What this sample course explores" : "What you’ll learn"}</h2>
                <ul className="outcome-list">
                  {course.outcomes.map((outcome) => (
                    <li key={outcome}><span className="outcome-check" aria-hidden="true">✓</span><span>{outcome}</span></li>
                  ))}
                </ul>
              </section>
            ) : null}

            <section className="detail-section" id="curriculum" aria-labelledby="curriculum-heading">
              <h2 id="curriculum-heading">{isDemo ? "Sample curriculum" : "Course curriculum"}</h2>
              <p className="section-copy">
                {isDemo
                  ? "This outline demonstrates the planned course structure. Lessons are not playable in this milestone."
                  : "Review the published sections and lesson titles. Lesson playback and enrollment are not enabled yet."}
              </p>
              {course.sections.length > 0 ? course.sections.map((section, index) => (
                <div className="detail-section" key={`${section.title}-${index}`}>
                  <h3 className="eyebrow">Section {index + 1} · {section.title}</h3>
                  {section.lessonTitles.length > 0 ? (
                    <ul className="module-list">
                      {section.lessonTitles.map((lesson, lessonIndex) => (
                        <li key={`${lesson}-${lessonIndex}`}>
                          <span>{lesson}</span>
                          <small>{isDemo ? `Sample lesson ${lessonIndex + 1}` : `Lesson ${lessonIndex + 1}`}</small>
                        </li>
                      ))}
                    </ul>
                  ) : <p className="section-copy">No lessons are listed in this section yet.</p>}
                </div>
              )) : <p className="section-copy">The curriculum for this course is being prepared.</p>}
            </section>
          </article>

          <aside className="detail-aside" aria-label={isDemo ? "Sample course summary" : "Course summary"}>
            <div className="course-art" data-tone={course.tone} aria-hidden="true">
              <span className="course-art-label">{course.category}{isDemo ? " · sample" : ""}</span>
            </div>
            <h2>{course.title}</h2>
            {course.subtitle ? <p>{course.subtitle}</p> : null}
            <p className="course-instructor">{isDemo ? "Sample instructor" : "Instructor"} · {course.instructorName}</p>
            <p><strong>{course.lessonCount} {isDemo ? "sample " : ""}{course.lessonCount === 1 ? "lesson" : "lessons"}</strong><br />{course.level}</p>
            <Link className="button-solid" href="#curriculum">{isDemo ? "Read the outline" : "View curriculum"} <span aria-hidden="true">↓</span></Link>
            <small>
              {isDemo
                ? "No sign-in, enrollment, playback, or progress is recorded. Those features require later milestones and service setup."
                : "This course is published for discovery. Enrollment and lesson playback are not available in this stage."}
            </small>
          </aside>
        </div>
      </div>
    </main>
  );
}
