import { useEffect, useRef, type ReactNode } from "react";

/** A desktop sheet: background is inert, focus stays inside, Escape closes it. */
export function DesktopDialog({ children, label, onClose, className = "" }: {
  children: ReactNode; label: string; onClose: () => void; className?: string;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    const previous = document.activeElement as HTMLElement | null;
    dialog?.showModal();
    return () => { dialog?.close(); previous?.focus(); };
  }, []);
  return <dialog ref={ref} className={`desktop-dialog ${className}`} aria-label={label}
    onCancel={event => { event.preventDefault(); onClose(); }}
    onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
    {children}
  </dialog>;
}
