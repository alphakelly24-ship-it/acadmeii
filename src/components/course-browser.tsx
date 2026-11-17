"use client";

import { useMemo, useState } from "react";
import { CourseCard } from "@/components/course-card";
import { filterCourses } from "@/lib/course-filter";
import type { CatalogCourse } from "@/lib/catalog-types";

type CourseBrowserProps = {
  courses: readonly CatalogCourse[];
  categories: readonly string[];
  source: "demo" | "live" | "error";
};

export function CourseBrowser({ courses, categories, source }: CourseBrowserProps) {
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState("All topics");
  const isDemo = source === "demo";

  const filteredCourses = useMemo(
    () => filterCourses(courses, query, category),
    [category, courses, query],
  );

  if (source === "error") {
    return (
      <section aria-labelledby="course-results-heading">
        <h2 className="sr-only" id="course-results-heading">Course results</h2>
        <div className="empty-state" role="alert">
          <h2>Courses are temporarily unavailable.</h2>
          <p>We couldn’t load the course catalog. Please try again later.</p>
        </div>
      </section>
    );
  }

  if (source === "live" && courses.length === 0) {
    return (
      <section aria-labelledby="course-results-heading">
        <h2 className="sr-only" id="course-results-heading">Course results</h2>
        <div className="empty-state">
          <h2>No published courses yet.</h2>
          <p>There are no courses available in the catalog yet. Check back soon.</p>
        </div>
      </section>
    );
  }

  return (
    <section aria-labelledby="course-results-heading">
      <div className="catalog-controls">
        <div className="search-field">
          <label htmlFor="course-search">Search {isDemo ? "sample " : ""}courses</label>
          <input
            id="course-search"
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Try “design” or an instructor name"
            autoComplete="off"
          />
        </div>
        <div className="search-field">
          <label htmlFor="course-category">Filter by {isDemo ? "topic" : "category"}</label>
          <select
            className="category-select"
            id="course-category"
            value={category}
            onChange={(event) => setCategory(event.target.value)}
          >
            {categories.map((item) => <option key={item} value={item}>{item}</option>)}
          </select>
        </div>
      </div>
      <p className="results-line" aria-live="polite">
        {filteredCourses.length} {isDemo ? "sample " : ""}{filteredCourses.length === 1 ? "course" : "courses"} shown{isDemo ? " · demo content only" : ""}
      </p>
      <h2 className="sr-only" id="course-results-heading">Course results</h2>
      {filteredCourses.length > 0 ? (
        <div className="course-grid">
          {filteredCourses.map((course) => <CourseCard key={course.slug} course={course} />)}
        </div>
      ) : (
        <div className="empty-state">
          <h2>{isDemo ? "No sample courses" : "No courses"} match those filters.</h2>
          <p>Try another search or reset the category to see the full {isDemo ? "sample " : ""}catalog.</p>
          <button className="button-outline" type="button" onClick={() => { setQuery(""); setCategory("All topics"); }}>
            Clear search and filters
          </button>
        </div>
      )}
    </section>
  );
}
