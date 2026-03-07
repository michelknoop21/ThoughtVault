import { Component } from "react";
import type { ErrorInfo, ReactNode } from "react";

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("[ErrorBoundary]", error, info.componentStack);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          height: "100%",
          gap: 16,
          padding: 32,
          textAlign: "center",
          color: "var(--text-primary)",
          fontFamily: "var(--font-family)",
        }}>
          <div style={{
            width: 48,
            height: 48,
            borderRadius: 8,
            background: "rgba(188, 0, 22, 0.08)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 24,
            color: "var(--fill-system-critical)",
          }}>
            !
          </div>
          <h2 style={{ fontSize: 16, fontWeight: 600, margin: 0 }}>
            Er is iets misgegaan
          </h2>
          <p style={{
            fontSize: 13,
            color: "var(--text-secondary)",
            maxWidth: 400,
            lineHeight: 1.5,
            margin: 0,
          }}>
            {this.state.error?.message || "Onbekende fout"}
          </p>
          <button
            onClick={() => {
              this.setState({ hasError: false, error: null });
              window.location.hash = "/";
              window.location.reload();
            }}
            className="btn btn-accent"
            style={{
              fontFamily: "inherit",
            }}
          >
            Herlaad applicatie
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}
