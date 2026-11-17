import Link from "next/link";
import type { CatalogCourse } from "@/lib/catalog-types";

export function CourseCard({ course }: { course: CatalogCourse }) {
  const isDemo = course.source === "demo";

  return (
    <article className="course-card">
      <Link href={`/courses/${course.slug}`} aria-label={`View ${isDemo ? "sample " : ""}course: ${course.title}`}>
        <div className="course-art" data-tone={course.tone} aria-hidden="true">
          <span className="course-art-label">{course.category}{isDemo ? " · sample" : ""}</span>
        </div>
        <div className="course-card-body">
          <div className="course-meta">
            <span>{course.category}</span>
            <span>{course.lessonCount} {isDemo ? "sample " : ""}{course.lessonCount === 1 ? "lesson" : "lessons"}</span>
          </div>
          <h3>{course.title}</h3>
          <p>{course.subtitle}</p>
          <p className="course-instructor">{isDemo ? "Sample instructor" : "Instructor"} · {course.instructorName}</p>
          <div className="course-card-bottom">
            <span className="sample-tag">{isDemo ? "Demo content" : "Published"}</span>
            <span className="text-link" aria-hidden="true">View outline →</span>
          </div>
        </div>
      </Link>
    </article>
  );
}
