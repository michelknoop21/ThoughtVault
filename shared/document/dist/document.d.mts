export interface DocumentBranding {
  schemaVersion: 1;
  id: string;
  revision: number;
  name: string;
  company: string;
  contact: string;
  layout: "compact" | "cover";
  textColor: string;
  headingColor: string;
  accentColor: string;
  bodyFont: "Carlito" | "Caladea";
  headingFont: "Carlito" | "Caladea";
  fontSize: number;
  lineHeight: number;
  marginTop: number;
  marginBottom: number;
  marginLeft: number;
  marginRight: number;
  header: string;
  footer: string;
  coverHeader: string;
  coverFooter: string;
  pageNumbers: boolean;
  runningHeader: boolean;
  runningFooter: boolean;
  logo: string;
  coverBanner: string;
  headerBanner: string;
  footerBanner: string;
}
export interface BrandingLibrary {
  schemaVersion: 1;
  defaultId: string | null;
  styles: DocumentBranding[];
}
export interface DocumentOptions {
  html: string;
  title?: string;
  subtitle?: string;
  branding?: DocumentBranding | string | null;
  editable?: boolean;
}
export function validateBranding(value: unknown): DocumentBranding;
export function validateLibrary(value: unknown): BrandingLibrary;
export function parseBranding(text: string): DocumentBranding;
export function blankBranding(): DocumentBranding;
export function standardBranding(): DocumentBranding;
export function renderDocument(options: DocumentOptions): string;
export function standalone(options: DocumentOptions): Promise<string>;
export function ready(doc?: Document): Promise<void>;
export function paginate(doc?: Document): Promise<void>;
export function fitDocument(doc?: Document): void;
export function wordDocument(options: DocumentOptions): Promise<Uint8Array>;
export function sanitizeContent(html: string): string;
export function mountEditor(
  root: HTMLElement,
  options?: {
    library?: BrandingLibrary;
    onSave?: (value: BrandingLibrary) => Promise<void>;
    onExport?: (value: { name: string; text: string }) => Promise<void>;
  },
): { loadLibrary(value: BrandingLibrary): void; destroy(): void };
