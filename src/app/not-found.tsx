import Link from "next/link";

export default function NotFound() {
  return (
    <main id="main-content" className="catalog-page">
      <div className="page-shell empty-state">
        <p className="eyebrow">That page is not here</p>
        <h1>We couldn’t find that course.</h1>
        <p>Course details in this milestone come from a small local sample catalog.</p>
        <Link className="button-solid" href="/courses">Return to sample courses</Link>
      </div>
    </main>
  );
}
