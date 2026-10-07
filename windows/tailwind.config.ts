import type { Config } from "tailwindcss";

export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      colors: {
        accent: {
          DEFAULT: "#E50074",
          hover: "rgba(229,0,116,0.90)",
          pressed: "rgba(229,0,116,0.80)",
          light: "rgba(229,0,116,0.08)",
        },
        text: {
          primary: "var(--text-primary)",
          secondary: "var(--text-secondary)",
          tertiary: "var(--text-tertiary)",
          disabled: "var(--text-disabled)",
          error: "var(--text-error)",
          success: "var(--text-success)",
        },
        surface: {
          DEFAULT: "var(--surface-primary)",
          secondary: "var(--surface-secondary)",
          tertiary: "var(--surface-tertiary)",
          card: "var(--card-bg)",
          elevated: "var(--card-bg-hover)",
        },
        fill: {
          control: "var(--fill-control)",
          "control-hover": "var(--fill-control-hover)",
        },
        stroke: {
          divider: "var(--border-primary)",
          card: "var(--card-border)",
        },
        danger: "var(--status-error)",
        success: "var(--status-success)",
        warning: "var(--status-warning)",
      },
      fontFamily: {
        sans: [
          "SF Pro Rounded",
          "SF Pro",
          "Segoe UI Variable",
          "Segoe UI",
          "-apple-system",
          "system-ui",
          "sans-serif",
        ],
      },
      borderRadius: {
        xs: "6px",
        sm: "12px",
        DEFAULT: "12px",
        md: "16px",
        lg: "20px",
        xl: "25px",
      },
    },
  },
  plugins: [],
} satisfies Config;
