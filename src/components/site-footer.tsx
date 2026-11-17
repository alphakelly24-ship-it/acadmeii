import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="page-shell footer-inner">
        <div>
          <Link className="brand-lockup" href="/" aria-label="Academi home">
            <BrandMark />
            <span className="brand-wordmark">academi</span>
          </Link>
          <p className="footer-note">A thoughtful place to build practical skills, one lesson at a time.</p>
        </div>
        <div>
          <nav className="footer-links" aria-label="Footer navigation">
            <Link href="/courses">Explore courses</Link>
            <Link href="/#approach">Our approach</Link>
          </nav>
          <p className="footer-copyright">© {new Date().getFullYear()} Academi. Sample course content is for demonstration.</p>
        </div>
      </div>
    </footer>
  );
}
