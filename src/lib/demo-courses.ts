import type { DemoCourse } from "@/lib/catalog-types";

export type { DemoCourse } from "@/lib/catalog-types";

export const demoCourses: DemoCourse[] = [
  {
    slug: "question-to-insight",
    source: "demo",
    title: "From question to insight",
    instructorName: "Avery Morgan",
    subtitle: "Turn a good question into a clearer decision.",
    category: "Research",
    level: "Beginner",
    lessonCount: 4,
    description: "A sample introduction to framing a research question, gathering useful signals, and explaining what the findings mean. This course outline is demonstration content only.",
    outcomes: ["Frame a question that can guide practical research.", "Separate observations from assumptions.", "Summarize a finding in plain language."],
    sections: [
      { title: "Start with the question", lessonTitles: ["Define the decision", "Write a focused question"] },
      { title: "Make sense of evidence", lessonTitles: ["Look for patterns", "Share one clear insight"] },
    ],
    tone: "sage",
  },
  {
    slug: "clear-digital-services",
    source: "demo",
    title: "Designing clear digital services",
    instructorName: "Jordan Lee",
    subtitle: "Make a complex journey easier to understand.",
    category: "Product design",
    level: "Beginner",
    lessonCount: 5,
    description: "A sample course about mapping a user journey, finding moments of friction, and shaping a more understandable service experience. No live instruction or enrollment is available in this demo.",
    outcomes: ["Sketch a simple service journey.", "Spot unclear steps and handoffs.", "Use plain language to improve one interaction."],
    sections: [
      { title: "See the whole journey", lessonTitles: ["Choose a user goal", "Map the important steps"] },
      { title: "Improve the experience", lessonTitles: ["Find friction", "Rewrite a confusing moment", "Review the journey"] },
    ],
    tone: "ochre",
  },
  {
    slug: "typescript-everyday-projects",
    source: "demo",
    title: "TypeScript for everyday projects",
    instructorName: "Sam Rivera",
    subtitle: "Build confidence with types, one example at a time.",
    category: "Development",
    level: "Beginner",
    lessonCount: 6,
    description: "A sample learning path that introduces readable types, safer function inputs, and practical object shapes for a small application. The lesson names illustrate the future course structure.",
    outcomes: ["Add useful types to common values and functions.", "Describe a small data model with an interface.", "Read and improve a simple type error."],
    sections: [
      { title: "Types that help", lessonTitles: ["Start with values", "Type a function", "Use a union"] },
      { title: "Shape your data", lessonTitles: ["Model an object", "Work with arrays", "Review a small example"] },
    ],
    tone: "blue",
  },
  {
    slug: "write-for-the-reader",
    source: "demo",
    title: "Write with the reader in mind",
    instructorName: "Riley Chen",
    subtitle: "Make important information easier to act on.",
    category: "Communication",
    level: "Intermediate",
    lessonCount: 4,
    description: "A sample course about audience, structure, and editing for clarity. The fictional outline is included to demonstrate course discovery and curriculum presentation.",
    outcomes: ["Identify what a reader needs to do.", "Organize information around that task.", "Edit a paragraph for clarity and tone."],
    sections: [
      { title: "Know the reader", lessonTitles: ["Start with a need", "Choose the next action"] },
      { title: "Make the message clear", lessonTitles: ["Build a useful structure", "Edit for understanding"] },
    ],
    tone: "sage",
  },
];

export const courseCategories = ["All topics", ...Array.from(new Set(demoCourses.map((course) => course.category)))];

export function getDemoCourse(slug: string) {
  return demoCourses.find((course) => course.slug === slug);
}
