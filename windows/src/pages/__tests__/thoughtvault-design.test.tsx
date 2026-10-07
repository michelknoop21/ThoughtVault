import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { HomePage } from "../HomePage";
import { SettingsPage } from "../SettingsPage";
import { Sidebar } from "../../components/layout/Sidebar";

describe("current ThoughtVault interface", () => {
  it("keeps the approved settings navigation and new provider controls together", () => {
    const root = document.createElement("div");
    root.innerHTML = renderToStaticMarkup(<SettingsPage />);
    const tabs = root.querySelectorAll('nav[aria-label="Instellingen"] button');
    expect([...tabs].map(tab => tab.textContent)).toEqual(["Algemeen", "Verwerking", "Notulen", "Agenda", "Obsidian", "Geavanceerd"]);
    expect(root.querySelector('.processing-columns .processing-side')).not.toBeNull();
    expect(root.textContent).toContain("Jouw pc");
    expect(root.textContent).toContain("Ollama Cloud");
    expect(root.textContent).toContain("Cloudprovider");
    expect(root.textContent).toContain("Claude en ChatGPT");
    expect(root.textContent).not.toContain("Onboarding opnieuw doorlopen");
  });

  it("renders the current Home composition and keeps its actions reachable", () => {
    const html = renderToStaticMarkup(<MemoryRouter><Sidebar /><HomePage /></MemoryRouter>);
    const root = document.createElement("div");
    root.innerHTML = html;
    expect(root.querySelector('.thoughtvault-home[data-theme="dark"]')).not.toBeNull();
    expect(root.querySelector('input[aria-label="Zoek in je notulen"]')).not.toBeNull();
    expect(root.querySelector('section[aria-label="Nieuwe opname"]')).not.toBeNull();
    expect(root.querySelector('button[aria-label="Nieuwe opname voorbereiden"]')).not.toBeNull();
    expect(root.querySelector('section[aria-label="Snel vastleggen"]')).not.toBeNull();
    expect(root.textContent).toContain("Recente notities");
    expect(root.textContent).not.toContain("Wat wil je vandaag transcriberen?");
    expect(root.textContent).not.toContain("Recente sessies");
    for (const href of ["/recording", "/tasks", "/transcripts", "/profiles", "/people", "/settings"])
      expect(root.querySelector(`nav a[href="${href}"]`)).not.toBeNull();
    expect(root.querySelector('nav img[alt="ThoughtVault"]')).not.toBeNull();
  });
});
