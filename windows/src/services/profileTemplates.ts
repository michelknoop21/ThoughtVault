// Enriches built-in profiles with the rich system/notule prompts + HTML output
// templates shared with the macOS app (data/profileTemplates.json). Mirrors the
// macOS Profile.defaults enrichment so locally generated notulen match.

import templates from "../data/profileTemplates.json";
import type { Profile } from "../types";

interface TemplateEntry {
  id: string;
  name: string;
  description?: string;
  icon?: string;
  systemPrompt?: string;
  notulePrompt?: string;
  template?: string;
}

const ENTRIES = templates as TemplateEntry[];

/**
 * Returns the profile enriched with its bundled template (by id). User-authored
 * profiles that already carry their own output template are returned untouched.
 */
export function enrichProfile(profile: Profile): Profile {
  if (profile.output_template || profile.notule_template) return profile;
  const entry = ENTRIES.find((e) => e.id === profile.id);
  if (!entry) return profile;
  return {
    ...profile,
    system_prompt: entry.systemPrompt ?? profile.system_prompt,
    notule_prompt: entry.notulePrompt ?? profile.notule_prompt,
    output_template: entry.template ?? profile.output_template,
  };
}
