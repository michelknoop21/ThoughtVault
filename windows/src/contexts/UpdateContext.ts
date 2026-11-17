import { createContext } from "react";
import type { useUpdateCheck } from "../hooks/useUpdateCheck";
export const UpdateContext = createContext<ReturnType<typeof useUpdateCheck> | null>(null);
