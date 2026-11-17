import type { Metadata } from "next";
import { CourseBrowser } from "@/components/course-browser";
import { getCatalogData } from "@/lib/catalog-data";

export const metadata: Metadata = { title: "Explore courses" };

export default async function CoursesPage() {
  const catalog = await getCatalogData();
  const isDemo = catalog.kind === "demo";
  const isError = catalog.kind === "error";

  return (
    <main id="main-content" className="catalog-page">
      <div className="page-shell">
        <div className="catalog-heading">
          <div>
            <p className="eyebrow">Browse Academi</p>
            <h1 className="section-heading">Find a subject worth your time.</h1>
            <p className="section-copy">
              {isDemo
                ? "Search the sample catalog. These course outlines are demonstration content only."
                : isError
                  ? "The course catalog could not be loaded right now."
                  : "Explore published courses, then search by topic, instructor, or course details."}
            </p>
          </div>
          <span className="sample-tag">
            {isDemo ? "Sample catalog" : isError ? "Catalog unavailable" : "Published courses"}
          </span>
        </div>
        <CourseBrowser
          courses={catalog.courses}
          categories={catalog.categories}
          source={catalog.kind}
        />
      </div>
    </main>
  );
}
