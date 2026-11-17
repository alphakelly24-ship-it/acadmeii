import type { CatalogCourse } from "@/lib/catalog-types";

const normalize = (value: string) => value.normalize("NFKC").toLocaleLowerCase("en-US");

export function filterCourses(
  courses: readonly CatalogCourse[],
  query: string,
  selectedCategory: string,
): CatalogCourse[] {
  const terms = normalize(query).trim().split(/\s+/).filter(Boolean);

  return courses.filter((course) => {
    if (selectedCategory !== "All topics" && course.category !== selectedCategory) {
      return false;
    }

    if (terms.length === 0) return true;

    const searchableText = [
      course.title,
      course.subtitle,
      course.description,
      course.instructorName,
      course.category,
      course.level,
      ...course.outcomes,
      ...course.sections.flatMap((section) => [section.title, ...section.lessonTitles]),
    ]
      .map(normalize)
      .join(" ");

    return terms.every((term) => searchableText.includes(term));
  });
}
