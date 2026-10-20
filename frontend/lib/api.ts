import { z } from "zod";

import { userManager } from "@/lib/auth";

/** Browser code must reach the API through the published port; server components
 *  resolve the Compose service name instead. */
export function apiBaseUrl(): string {
  if (typeof window === "undefined") {
    return process.env.INTERNAL_API_URL ?? "http://backend:8000";
  }
  return process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export async function request<T>(
  path: string,
  schema: z.ZodType<T>,
  init?: RequestInit,
): Promise<T> {
  let response: Response;
  try {
    const user = await userManager.getUser();
    const headers = new Headers(init?.headers);
    headers.set("Content-Type", "application/json");
    if (user?.access_token) {
      headers.set("Authorization", `Bearer ${user.access_token}`);
    }
    response = await fetch(`${apiBaseUrl()}${path}`, {
      ...init,
      cache: "no-store",
      headers,
    });
  } catch {
    throw new ApiError(0, "Could not reach the API");
  }

  if (!response.ok) {
    const detail = await response
      .json()
      .then((body) => (typeof body?.detail === "string" ? body.detail : null))
      .catch(() => null);
    throw new ApiError(
      response.status,
      detail ?? `Request failed (${response.status})`,
    );
  }

  if (response.status === 204) {
    return schema.parse(undefined);
  }
  return schema.parse(await response.json());
}

/* --- schemas mirroring the API contract in README section 5 --- */

export const itemStatuses = ["todo", "in_progress", "done"] as const;
export const itemStatusSchema = z.enum(itemStatuses);

export const itemSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  status: itemStatusSchema,
  created_at: z.string(),
  updated_at: z.string(),
});

export const itemListSchema = z.object({
  items: z.array(itemSchema),
  total: z.number().int(),
});

export const healthSchema = z.object({
  status: z.string(),
  database: z.string(),
});

export const itemInputSchema = z.object({
  name: z.string().min(1, "Name is required").max(120, "Name is too long"),
  description: z.string().max(2000, "Description is too long").optional(),
  status: itemStatusSchema,
});

export const agendaItemSchema = z.object({
  title: z.string(),
  duration_minutes: z.number().int().positive().nullable().optional(),
  notes: z.string().nullable().optional(),
});

export const actionItemSchema = z.object({
  description: z.string(),
  owner: z.string().nullable().optional(),
  due_date: z.string().nullable().optional(),
});

export const parsedAgendaSchema = z.object({
  title: z.string(),
  start_at: z.string(),
  duration_minutes: z.number().int().positive(),
  participant_count: z.number().int().nonnegative(),
  agenda_items: z.array(agendaItemSchema),
  action_items: z.array(actionItemSchema),
});

export const parserResponseSchema = z.object({
  agenda: parsedAgendaSchema,
  ai_suggestion: parsedAgendaSchema,
  model: z.string(),
  prompt_version: z.string(),
});

export const meetingSchema = parsedAgendaSchema.extend({
  id: z.string(),
  ai_suggestion: parsedAgendaSchema.nullable(),
  ai_model: z.string().nullable(),
  ai_prompt_version: z.string().nullable(),
});

export const meetingListSchema = z.object({
  meetings: z.array(meetingSchema),
  total: z.number().int(),
});

export type ItemStatus = z.infer<typeof itemStatusSchema>;
export type Item = z.infer<typeof itemSchema>;
export type ItemList = z.infer<typeof itemListSchema>;
export type Health = z.infer<typeof healthSchema>;
export type ItemInput = z.infer<typeof itemInputSchema>;
export type ParsedAgenda = z.infer<typeof parsedAgendaSchema>;
export type ParserResponse = z.infer<typeof parserResponseSchema>;
export type Meeting = z.infer<typeof meetingSchema>;
export type MeetingInput = ParsedAgenda & {
  ai_suggestion?: ParsedAgenda;
  ai_model?: string;
  ai_prompt_version?: string;
};

/* --- endpoints --- */

export const api = {
  readiness: () => request("/api/v1/health/ready", healthSchema),

  listItems: (params: { limit?: number; offset?: number } = {}) => {
    const query = new URLSearchParams();
    if (params.limit !== undefined) query.set("limit", String(params.limit));
    if (params.offset !== undefined) query.set("offset", String(params.offset));
    const suffix = query.size > 0 ? `?${query}` : "";
    return request(`/api/v1/items${suffix}`, itemListSchema);
  },

  createItem: (payload: ItemInput) =>
    request("/api/v1/items", itemSchema, {
      method: "POST",
      body: JSON.stringify(payload),
    }),

  updateItem: (id: string, payload: Partial<ItemInput>) =>
    request(`/api/v1/items/${id}`, itemSchema, {
      method: "PATCH",
      body: JSON.stringify(payload),
    }),

  deleteItem: (id: string) =>
    request(`/api/v1/items/${id}`, z.undefined(), { method: "DELETE" }),

  listMeetings: () => request("/api/v1/meetings", meetingListSchema),

  createMeeting: (payload: MeetingInput) =>
    request("/api/v1/meetings", meetingSchema, {
      method: "POST",
      body: JSON.stringify(payload),
    }),
};

export async function parseAgenda(
  text: string,
  signal?: AbortSignal,
): Promise<ParserResponse> {
  const parserUrl = process.env.NEXT_PUBLIC_AGENDA_PARSER_URL;
  if (!parserUrl) throw new ApiError(0, "Agenda parser is not configured");
  const user = await userManager.getUser();
  if (!user?.access_token)
    throw new ApiError(401, "Sign in before parsing an agenda");

  let response: Response;
  try {
    response = await fetch(parserUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${user.access_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        text,
        today: new Date().toISOString().slice(0, 10),
        tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
      }),
      signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError")
      throw error;
    throw new ApiError(0, "Could not reach the agenda parser");
  }
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new ApiError(
      response.status,
      body?.detail ?? `Parsing failed (${response.status})`,
    );
  }
  return parserResponseSchema.parse(await response.json());
}
