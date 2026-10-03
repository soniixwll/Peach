import { afterEach, describe, expect, it, vi } from "vitest";

import { ApiError, api, itemListSchema, request } from "@/lib/api";
import { userManager } from "@/lib/auth";

function mockFetch(body: unknown, init: { status?: number } = {}) {
  const status = init.status ?? 200;
  return vi.spyOn(globalThis, "fetch").mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response);
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("api", () => {
  it("parses a list response", async () => {
    mockFetch({ items: [], total: 0 });
    await expect(api.listItems()).resolves.toEqual({ items: [], total: 0 });
  });

  it("passes pagination through as query parameters", async () => {
    const spy = mockFetch({ items: [], total: 0 });
    await api.listItems({ limit: 5, offset: 10 });
    expect(spy.mock.calls[0][0]).toContain("/api/v1/items?limit=5&offset=10");
  });

  it("attaches the authenticated user's access token", async () => {
    vi.spyOn(userManager, "getUser").mockResolvedValue({
      access_token: "test-access-token",
      id_token: "test-id-token",
    } as Awaited<ReturnType<typeof userManager.getUser>>);
    const spy = mockFetch({ items: [], total: 0 });

    await api.listItems();

    const headers = spy.mock.calls[0][1]?.headers as Headers;
    expect(headers.get("Authorization")).toBe("Bearer test-access-token");
    expect(headers.get("Authorization")).not.toContain("test-id-token");
  });

  it("never substitutes the ID token for a missing access token", async () => {
    vi.spyOn(userManager, "getUser").mockResolvedValue({
      access_token: "",
      id_token: "test-id-token",
    } as Awaited<ReturnType<typeof userManager.getUser>>);
    const spy = mockFetch({ items: [], total: 0 });

    await api.listItems();

    const headers = spy.mock.calls[0][1]?.headers as Headers;
    expect(headers.has("Authorization")).toBe(false);
  });

  it("preserves request headers while adding authorization", async () => {
    vi.spyOn(userManager, "getUser").mockResolvedValue({
      access_token: "test-access-token",
    } as Awaited<ReturnType<typeof userManager.getUser>>);
    const spy = mockFetch({ items: [], total: 0 });

    await request("/api/v1/items", itemListSchema, {
      headers: { "X-Test-Header": "preserved" },
    });

    const headers = spy.mock.calls[0][1]?.headers as Headers;
    expect(headers.get("X-Test-Header")).toBe("preserved");
    expect(headers.get("Authorization")).toBe("Bearer test-access-token");
  });

  it("raises ApiError carrying the detail from the backend", async () => {
    mockFetch({ detail: "Item not found" }, { status: 404 });
    await expect(api.listItems()).rejects.toMatchObject({
      status: 404,
      message: "Item not found",
    });
  });

  it("raises ApiError when the network is unreachable", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => {
      throw new TypeError("failed");
    });
    await expect(api.listItems()).rejects.toBeInstanceOf(ApiError);
  });
});
