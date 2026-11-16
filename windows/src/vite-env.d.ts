/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_HELP_URL?: string;
}

declare module "*.png" {
  const src: string;
  export default src;
}

declare module "*.svg" {
  const src: string;
  export default src;
}

declare module "*.jpg" {
  const src: string;
  export default src;
}

declare module "*.ico" {
  const src: string;
  export default src;
}
