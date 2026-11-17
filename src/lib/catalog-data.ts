import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import { courseCategories, demoCourses, getDemoCourse } from "@/lib/demo-courses";
import type { CatalogCourse, CourseTone } from "@/lib/catalog-types";

const COURSE_SELECT = `
  slug,
  title,
  subtitle,
  description,
  level,
  published_at,
  category:categories!courses_category_id_fkey(name),
  instructor:instructor_profiles!courses_instructor_id_fkey(public_name),
  outcomes:course_outcomes!course_outcomes_course_id_fkey(position,outcome),
  sections:course_sections!course_sections_course_id_fkey(
    title,
    position,
    lessons:lessons!lessons_section_course_fk(title,position)
  )
`;

type LiveCourseRow = {
  slug: string;
  title: string;
  subtitle: string | null;
  description: string | null;
  level: string;
  published_at: string | null;
  category: { name: string } | null;
  instructor: { public_name: string } | null;
  outcomes: { position: number; outcome: string }[] | null;
  sections: {
    title: string;
    position: number;
    lessons: { title: string; position: number }[] | null;
  }[] | null;
};

type LiveCategoryRow = {
  name: string;
  sort_order: number;
};

export type CatalogData =
  | { kind: "demo" | "live"; courses: CatalogCourse[]; categories: string[] }
  | { kind: "error"; courses: []; categories: string[] };

export type CourseLookup =
  | { kind: "found"; course: CatalogCourse }
  | { kind: "not-found" }
  | { kind: "error" };

export function hasSupabaseCatalogConfig(): boolean {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL &&
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  );
}

function formatLevel(level: string): string {
  const labels: Record<string, string> = {
    beginner: "Beginner",
    intermediate: "Intermediate",
    advanced: "Advanced",
    all_levels: "All levels",
  };
  return labels[level] ?? level.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function toneForSlug(slug: string): CourseTone {
  const tones: CourseTone[] = ["sage", "ochre", "blue"];
  const hash = Array.from(slug).reduce((value, character) => value + character.charCodeAt(0), 0);
  return tones[hash % tones.length];
}

function mapLiveCourse(row: LiveCourseRow): CatalogCourse {
  const sections = [...(row.sections ?? [])]
    .sort((left, right) => left.position - right.position)
    .map((section) => ({
      title: section.title,
      lessonTitles: [...(section.lessons ?? [])]
        .sort((left, right) => left.position - right.position)
        .map((lesson) => lesson.title),
    }));

  return {
    slug: row.slug,
    title: row.title,
    instructorName: row.instructor?.public_name ?? "Instructor",
    subtitle: row.subtitle ?? "",
    category: row.category?.name ?? "Uncategorized",
    level: formatLevel(row.level),
    lessonCount: sections.reduce((total, section) => total + section.lessonTitles.length, 0),
    description: row.description ?? "",
    outcomes: [...(row.outcomes ?? [])]
      .sort((left, right) => left.position - right.position)
      .map((outcome) => outcome.outcome),
    sections,
    tone: toneForSlug(row.slug),
    source: "live",
  };
}

function categoryOptions(rows: LiveCategoryRow[], courses: CatalogCourse[] = []): string[] {
  const names = new Set(rows.map((row) => row.name.trim()).filter(Boolean));
  for (const course of courses) {
    if (course.category && course.category !== "Uncategorized") names.add(course.category);
  }
  return ["All topics", ...Array.from(names)];
}

export async function getCatalogData(): Promise<CatalogData> {
  if (!hasSupabaseCatalogConfig()) {
    return { kind: "demo", courses: demoCourses, categories: courseCategories };
  }

  try {
    const supabase = await createClient();
    const [coursesResult, categoriesResult] = await Promise.all([
      supabase
        .from("courses")
        .select(COURSE_SELECT)
        .eq("status", "published")
        .order("published_at", { ascending: false }),
      supabase
        .from("categories")
        .select("name,sort_order")
        .order("sort_order", { ascending: true })
        .order("name", { ascending: true }),
    ]);

    const categoryRows = (categoriesResult.data ?? []) as LiveCategoryRow[];
    if (coursesResult.error || categoriesResult.error) {
      return {
        kind: "error",
        courses: [],
        categories: categoryOptions(categoryRows),
      };
    }

    const rows = (coursesResult.data ?? []) as unknown as LiveCourseRow[];
    const courses = rows.map(mapLiveCourse);
    return {
      kind: "live",
      courses,
      categories: categoryOptions(categoryRows, courses),
    };
  } catch {
    return { kind: "error", courses: [], categories: ["All topics"] };
  }
}

export const getCatalogCourseBySlug = cache(async (slug: string): Promise<CourseLookup> => {
  if (!hasSupabaseCatalogConfig()) {
    const demoCourse = getDemoCourse(slug);
    return demoCourse ? { kind: "found", course: demoCourse } : { kind: "not-found" };
  }

  try {
    const supabase = await createClient();
    const { data, error } = await supabase
      .from("courses")
      .select(COURSE_SELECT)
      .eq("slug", slug)
      .eq("status", "published")
      .maybeSingle();

    if (error) return { kind: "error" };
    if (!data) {
      // The homepage still features explicitly labelled demo cards. Keep those
      // outline URLs working without inserting sample rows into the live catalog.
      const demoCourse = getDemoCourse(slug);
      return demoCourse ? { kind: "found", course: demoCourse } : { kind: "not-found" };
    }

    return {
      kind: "found",
      course: mapLiveCourse(data as unknown as LiveCourseRow),
    };
  } catch {
    return { kind: "error" };
  }
});
