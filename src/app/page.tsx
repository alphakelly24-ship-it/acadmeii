import Image from "next/image";
import Link from "next/link";
import { CourseCard } from "@/components/course-card";
import { demoCourses } from "@/lib/demo-courses";

export default function HomePage() {
  return (
    <main id="main-content">
      <section className="hero">
        <div className="page-shell hero-grid">
          <div className="hero-copy">
            <p className="eyebrow">A thoughtful start to learning</p>
            <h1 className="hero-title">Build a skill.<br /><em>Make it yours.</em></h1>
            <p className="hero-description">
              Find a clear path into practical ideas and new ways of working. Academi is building a more considered place to learn, one lesson at a time.
            </p>
            <div className="hero-actions">
              <Link className="button-solid" href="/courses">Explore sample courses <span aria-hidden="true">↗</span></Link>
              <Link className="text-link" href="#approach">See our approach</Link>
            </div>
            <p className="demo-note"><span className="demo-dot" aria-hidden="true" /> Early foundation · course examples are demonstrations, not live offerings</p>
          </div>
          <div className="hero-visual">
            <div className="hero-photo-wrap">
              <Image className="hero-photo" src="/images/learning-space.jpg" alt="A learner working through an online lesson at a laptop" width={3000} height={1999} priority sizes="(max-width: 680px) 90vw, 52vw" />
              <span className="photo-caption">A little room to grow</span>
            </div>
            <div className="hero-stamp" aria-hidden="true"><span>Learn<br />well</span><small>at your pace</small></div>
          </div>
        </div>
      </section>

      <section className="intro-band" id="approach">
        <div className="page-shell intro-grid">
          <div>
            <p className="eyebrow">A clearer learning path</p>
            <h2 className="section-heading">Good learning starts with knowing what comes next.</h2>
          </div>
          <div className="intro-aside">
            <p>Academi is being built around structured courses, useful lessons, and visible progress. This first foundation offers a small, searchable sample catalog; real accounts, enrollment, and saved learning data are planned for later milestones.</p>
          </div>
        </div>
      </section>

      <section className="catalog-preview page-shell" aria-labelledby="preview-heading">
        <div className="section-topline">
          <div>
            <p className="eyebrow">A first look</p>
            <h2 className="section-heading" id="preview-heading">Explore the sample catalog</h2>
            <p className="section-copy">These demonstration courses show how discovery and course outlines will feel. They are not published offerings.</p>
          </div>
          <Link className="text-link" href="/courses">View all sample courses <span aria-hidden="true">→</span></Link>
        </div>
        <div className="course-grid">
          {demoCourses.slice(0, 3).map((course) => <CourseCard key={course.slug} course={course} />)}
        </div>
      </section>
    </main>
  );
}
