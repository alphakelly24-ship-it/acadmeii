export type CourseTone = "sage" | "ochre" | "blue";

export type CatalogCourse = {
  slug: string;
  title: string;
  instructorName: string;
  subtitle: string;
  category: string;
  level: string;
  lessonCount: number;
  description: string;
  outcomes: string[];
  sections: { title: string; lessonTitles: string[] }[];
  tone: CourseTone;
  source: "demo" | "live";
};

export type DemoCourse = Omit<CatalogCourse, "source"> & {
  source: "demo";
};
