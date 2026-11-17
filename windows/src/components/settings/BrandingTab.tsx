import { useEffect, useRef, useState } from "react";
import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import { mountEditor } from "../../../../shared/document/dist/document.mjs";
import { useBrandingStore } from "../../stores/brandingStore";
export function BrandingTab() {
  const root = useRef<HTMLDivElement>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    let destroyed = false;
    let editor: ReturnType<typeof mountEditor> | undefined;
    void useBrandingStore
      .getState()
      .hydrate()
      .then(() => {
        if (destroyed || !root.current) return;
        editor = mountEditor(root.current, {
          library: useBrandingStore.getState().library,
          onSave: (value) => useBrandingStore.getState().save(value),
          onExport: async ({ name, text }) => {
            const path = await save({
              defaultPath: name,
              filters: [
                { name: "ThoughtVault-huisstijl", extensions: ["tvhuisstijl"] },
              ],
            });
            if (path) await writeTextFile(path, text);
          },
        });
      })
      .catch((e) => setError(String(e)));
    return () => {
      destroyed = true;
      editor?.destroy();
    };
  }, []);
  return (
    <>
      {error && <p role="alert">{error}</p>}
      <div ref={root} />
    </>
  );
}
