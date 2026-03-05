import type { Config } from "tailwindcss";

export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      colors: {
        // Yinga brand accent (#E50074 pink — replaces Windows blue)
        accent: {
          DEFAULT: "#E50074",
          hover: "rgba(229,0,116,0.90)",
          pressed: "rgba(229,0,116,0.80)",
          light: "rgba(229,0,116,0.08)",
        },
        // Semantic text tokens (map to CSS vars for auto dark-mode)
        text: {
          primary: "var(--text-primary)",
          secondary: "var(--text-secondary)",
          tertiary: "var(--text-tertiary)",
          disabled: "var(--text-disabled)",
          error: "var(--text-error)",
          success: "var(--text-success)",
        },
        // Semantic surface tokens
        surface: {
          DEFAULT: "var(--surface-default)",
          card: "var(--surface-card)",
          elevated: "var(--surface-elevated)",
          flyout: "var(--surface-flyout)",
        },
        // Fill tokens
        fill: {
          control: "var(--fill-control-default)",
          "control-secondary": "var(--fill-control-secondary)",
        },
        // Stroke tokens
        stroke: {
          divider: "var(--stroke-divider)",
          card: "var(--stroke-card)",
          control: "var(--stroke-control-secondary)",
        },
        // Status
        danger: "var(--fill-system-critical)",
        success: "var(--fill-system-success)",
        warning: "var(--fill-system-caution)",
      },
      fontFamily: {
        sans: [
          "Segoe UI Variable",
          "Segoe UI",
          "-apple-system",
          "system-ui",
          "sans-serif",
        ],
      },
      borderRadius: {
        sm: "4px",
        DEFAULT: "6px",
        md: "8px",
        lg: "12px",
        xl: "12px",
      },
    },
  },
  plugins: [],
} satisfies Config;
