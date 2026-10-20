/** Keep generated content, but let the app own document styling and hierarchy. */
export function prepareNotuleHtml(html: string, _title: string): string {
  const document = new DOMParser().parseFromString(html, "text/html");
  document.querySelectorAll("style, link[rel=stylesheet]").forEach((node) => node.remove());
  document.body.querySelectorAll("[style]").forEach((node) => node.removeAttribute("style"));

  document.body.querySelectorAll("h1").forEach((node) => node.remove());

  return document.body.innerHTML;
}
