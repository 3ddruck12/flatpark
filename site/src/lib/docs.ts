// Locale-aware access to the docs library (the `docs` content collection).
//
// English is the source. A translation sits next to its page
// (`users/setup.zh-Hans.md`) and replaces it under that locale; an untranslated
// page renders its English body under the localised URL, so the sidebar, the
// hreflang set and the sitemap are the same in every locale.
import { getCollection, type CollectionEntry } from 'astro:content';
import { defaultLang, type Lang } from '../i18n';
import { docSlug, docUrl, splitDocId } from './docs-paths.mjs';

type Entry = CollectionEntry<'docs'>;

export interface Doc {
  /** English id: `users/setup`, `users/README`, `README`. */
  base: string;
  /** Path under /docs/: `users/setup`, `users`, ''. */
  slug: string;
  /** Top-level directory, '' for the library index. */
  section: string;
  /** Subdirectory within the section (`formats`), '' for a page at its top. */
  group: string;
  isIndex: boolean;
  title: string;
  description: string;
  order: number;
  entry: Entry;
  /** The file this locale renders, relative to the repo root. */
  file: string;
}

/** A subdirectory of a section (`packagers/formats/`), its README as the heading. */
export interface NavGroup {
  dir: string;
  index?: Doc;
  title: string;
  order: number;
  pages: Doc[];
}

export type NavItem = { page: Doc } | { group: NavGroup };

export interface NavSection {
  section: string;
  index?: Doc;
  title: string;
  /** Pages and subdirectories, in sidebar order. */
  items: NavItem[];
}

// Sidebar order. A new top-level directory still shows up, after these.
const SECTION_ORDER = ['users', 'developers', 'packagers', 'reviewers', 'reference', 'project'];

/** The page's `# H1`, which is its title on GitHub as well. */
function titleOf(entry: Entry): string {
  const m = /^#\s+(.+?)\s*#*\s*$/m.exec(entry.body ?? '');
  return m ? m[1].replace(/[*_`]/g, '') : entry.id;
}

function toDoc(base: string, entry: Entry): Doc {
  const slug = docSlug(base);
  const parts = slug.split('/');
  const isIndex = base === 'README' || base.endsWith('/README');
  return {
    base,
    slug,
    section: parts[0] ?? '',
    group: parts.length > (isIndex ? 1 : 2) ? parts[1] : '',
    isIndex,
    title: titleOf(entry),
    description: entry.data.description ?? '',
    order: entry.data.order,
    entry,
    file: `docs/${entry.id}.md`,
  };
}

/** Every published doc as it should appear in `lang`. */
export async function getDocsFor(lang: Lang): Promise<Doc[]> {
  const all = (await getCollection('docs')).filter((e) => e.data.publish);
  const english = new Map<string, Entry>();
  const translated = new Map<string, Entry>();
  for (const entry of all) {
    const { base, lang: entryLang } = splitDocId(entry.id);
    if (entryLang === defaultLang) english.set(base, entry);
    else if (entryLang === lang) translated.set(base, entry);
  }
  return [...english.entries()].map(([base, entry]) => toDoc(base, translated.get(base) ?? entry));
}

const byOrder = (a: Doc, b: Doc) => a.order - b.order || a.title.localeCompare(b.title);

const orderOf = (item: NavItem) => ('page' in item ? item.page.order : item.group.order);
const titleOfItem = (item: NavItem) => ('page' in item ? item.page.title : item.group.title);

/**
 * Sidebar: one group per top-level directory, its README as the heading. A
 * subdirectory nests one level under it, placed by its own README's `order`.
 */
export function buildNav(docs: Doc[]): NavSection[] {
  const sections = new Map<string, NavSection & { groups: Map<string, NavGroup> }>();
  for (const doc of docs) {
    if (!doc.section) continue;
    const s = sections.get(doc.section) ?? {
      section: doc.section,
      title: doc.section,
      items: [],
      groups: new Map(),
    };
    sections.set(doc.section, s);
    if (doc.isIndex && doc.slug === doc.section) {
      s.index = doc;
      s.title = doc.title;
    } else if (doc.group) {
      const dir = `${doc.section}/${doc.group}`;
      let g = s.groups.get(dir);
      if (!g) {
        g = { dir, title: doc.group, order: Number.MAX_SAFE_INTEGER, pages: [] };
        s.groups.set(dir, g);
        s.items.push({ group: g });
      }
      if (doc.isIndex) {
        g.index = doc;
        g.title = doc.title;
        g.order = doc.order;
      } else {
        g.pages.push(doc);
      }
    } else {
      s.items.push({ page: doc });
    }
  }
  const rank = (name: string) => {
    const i = SECTION_ORDER.indexOf(name);
    return i < 0 ? SECTION_ORDER.length : i;
  };
  return [...sections.values()]
    .map(({ groups, ...s }) => {
      for (const g of groups.values()) g.pages.sort(byOrder);
      s.items.sort((a, b) => orderOf(a) - orderOf(b) || titleOfItem(a).localeCompare(titleOfItem(b)));
      return s;
    })
    .sort((a, b) => rank(a.section) - rank(b.section) || a.section.localeCompare(b.section));
}

/** Every doc in the sidebar, in sidebar order: each index before its pages. */
export function flattenNav(nav: NavSection[]): Doc[] {
  return nav.flatMap((s) => [
    ...(s.index ? [s.index] : []),
    ...s.items.flatMap((item) =>
      'page' in item ? [item.page] : [...(item.group.index ? [item.group.index] : []), ...item.group.pages],
    ),
  ]);
}

/** What an index page lists as cards: a section's items, or a group's pages. */
export function childrenOf(doc: Doc, nav: NavSection[]): Doc[] {
  if (!doc.isIndex) return [];
  const section = nav.find((s) => s.section === doc.section);
  if (!section) return [];
  if (doc.slug === section.section) {
    return section.items.flatMap((item) => ('page' in item ? [item.page] : item.group.index ? [item.group.index] : item.group.pages));
  }
  for (const item of section.items) {
    if ('group' in item && item.group.index?.base === doc.base) return item.group.pages;
  }
  return [];
}

export { docUrl };
