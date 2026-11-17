import { renderDocument, paginate, fitDocument } from "./render.js";
export async function showDocument(options) {
  const rendered = new DOMParser().parseFromString(
    renderDocument(options),
    "text/html",
  );
  document.head.replaceChildren(...rendered.head.childNodes);
  document.body.className = rendered.body.className;
  document.body.replaceChildren(...rendered.body.childNodes);
  if (options.editable) {
    const content = document.querySelector(".tv-content");
    content.id = "content";
    content.addEventListener("input", () =>
      window.webkit?.messageHandlers?.branding?.postMessage({
        type: "content",
        html: content.innerHTML,
      }),
    );
  } else await paginate(document);
  fitDocument(document);
  window.onresize = () => fitDocument(document);
}
