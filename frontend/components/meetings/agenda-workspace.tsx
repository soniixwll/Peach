"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Sparkles, X } from "lucide-react";
import { useRef, useState } from "react";
import { toast } from "sonner";

import { PageHeader } from "@/components/page-header";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  api,
  parseAgenda,
  type MeetingInput,
  type ParsedAgenda,
  type ParserResponse,
} from "@/lib/api";
import { cn } from "@/lib/utils";

type Draft = {
  title: string;
  start_at: string;
  duration_minutes: string;
  participant_count: string;
  agenda_items: string;
  action_items: string;
};

const emptyDraft: Draft = {
  title: "",
  start_at: "",
  duration_minutes: "60",
  participant_count: "0",
  agenda_items: "",
  action_items: "",
};

function localDateTime(iso: string): string {
  const value = new Date(iso);
  const local = new Date(value.getTime() - value.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 16);
}

function fromSuggestion(agenda: ParsedAgenda): Draft {
  return {
    title: agenda.title,
    start_at: localDateTime(agenda.start_at),
    duration_minutes: String(agenda.duration_minutes),
    participant_count: String(agenda.participant_count),
    agenda_items: agenda.agenda_items
      .map((item) =>
        [item.title, item.duration_minutes ?? "", item.notes ?? ""].join(" | "),
      )
      .join("\n"),
    action_items: agenda.action_items
      .map((item) =>
        [item.description, item.owner ?? "", item.due_date ?? ""].join(" | "),
      )
      .join("\n"),
  };
}

function payloadFromDraft(draft: Draft): ParsedAgenda {
  return {
    title: draft.title.trim(),
    start_at: new Date(draft.start_at).toISOString(),
    duration_minutes: Number(draft.duration_minutes),
    participant_count: Number(draft.participant_count),
    agenda_items: draft.agenda_items
      .split("\n")
      .map((line) => line.split("|").map((part) => part.trim()))
      .filter(([title]) => Boolean(title))
      .map(([title, duration, notes]) => ({
        title,
        ...(duration ? { duration_minutes: Number(duration) } : {}),
        ...(notes ? { notes } : {}),
      })),
    action_items: draft.action_items
      .split("\n")
      .map((line) => line.split("|").map((part) => part.trim()))
      .filter(([description]) => Boolean(description))
      .map(([description, owner, dueDate]) => ({
        description,
        ...(owner ? { owner } : {}),
        ...(dueDate ? { due_date: dueDate } : {}),
      })),
  };
}

export function AgendaWorkspace() {
  const queryClient = useQueryClient();
  const [pasted, setPasted] = useState("");
  const [draft, setDraft] = useState<Draft>(emptyDraft);
  const [provenance, setProvenance] = useState<ParserResponse | null>(null);
  const [suggested, setSuggested] = useState<Set<keyof Draft>>(new Set());
  const controller = useRef<AbortController | null>(null);
  const meetings = useQuery({
    queryKey: ["meetings"],
    queryFn: api.listMeetings,
  });

  const parser = useMutation({
    mutationFn: async () => {
      controller.current = new AbortController();
      return parseAgenda(pasted, controller.current.signal);
    },
    onSuccess: (result) => {
      setDraft(fromSuggestion(result.agenda));
      setProvenance(result);
      setSuggested(new Set(Object.keys(emptyDraft) as (keyof Draft)[]));
      toast.success(
        "Agenda suggestion ready — review every field before saving",
      );
    },
    onError: (error: Error) => {
      if (error.name !== "AbortError") toast.error(error.message);
    },
    onSettled: () => {
      controller.current = null;
    },
  });

  const save = useMutation({
    mutationFn: () => {
      const reviewed = payloadFromDraft(draft);
      const payload: MeetingInput = provenance
        ? {
            ...reviewed,
            ai_suggestion: provenance.ai_suggestion,
            ai_model: provenance.model,
            ai_prompt_version: provenance.prompt_version,
          }
        : reviewed;
      return api.createMeeting(payload);
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["meetings"] });
      setDraft(emptyDraft);
      setProvenance(null);
      setSuggested(new Set());
      setPasted("");
      toast.success("Agenda saved");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  function update(field: keyof Draft, value: string) {
    setDraft((current) => ({ ...current, [field]: value }));
    setSuggested((current) => {
      const next = new Set(current);
      next.delete(field);
      return next;
    });
  }

  const fieldClass = (field: keyof Draft) =>
    cn(
      suggested.has(field) &&
        "border-amber-400 bg-amber-50/50 dark:bg-amber-950/20",
    );

  return (
    <div className="grid gap-8">
      <PageHeader
        icon="🗓️"
        title="Meeting agendas"
        description="Paste an agenda for an AI suggestion, review it, then save through Peach."
      />

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Sparkles className="size-4" /> Paste an agenda
          </CardTitle>
        </CardHeader>
        <CardContent className="grid gap-3">
          <Textarea
            value={pasted}
            onChange={(event) => setPasted(event.target.value)}
            maxLength={10_000}
            rows={7}
            placeholder="Paste meeting notes, dates, topics, and actions here."
          />
          <div className="flex items-center gap-2">
            <Button
              type="button"
              onClick={() => parser.mutate()}
              disabled={!pasted.trim() || parser.isPending}
            >
              {parser.isPending ? "Parsing…" : "Parse with Nova"}
            </Button>
            {parser.isPending && (
              <Button
                type="button"
                variant="outline"
                onClick={() => controller.current?.abort()}
              >
                <X className="size-4" /> Cancel
              </Button>
            )}
            <span className="text-xs text-muted-foreground">
              {pasted.length}/10,000
            </span>
          </div>
          {parser.isError && parser.error.name !== "AbortError" && (
            <Alert variant="destructive">
              <AlertTitle>Could not parse this agenda</AlertTitle>
              <AlertDescription>{parser.error.message}</AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            Review and save
            {provenance && <Badge variant="secondary">AI suggestion</Badge>}
          </CardTitle>
        </CardHeader>
        <CardContent className="grid gap-5">
          <p className="text-sm text-muted-foreground">
            Amber fields came from AI. Editing a field clears its suggestion
            marker. You can always fill this form manually.
          </p>
          <div className="grid gap-2">
            <Label htmlFor="agenda-title">Title</Label>
            <Input
              id="agenda-title"
              className={fieldClass("title")}
              value={draft.title}
              onChange={(e) => update("title", e.target.value)}
            />
          </div>
          <div className="grid gap-4 sm:grid-cols-3">
            <div className="grid gap-2">
              <Label htmlFor="agenda-start">Start</Label>
              <Input
                id="agenda-start"
                type="datetime-local"
                className={fieldClass("start_at")}
                value={draft.start_at}
                onChange={(e) => update("start_at", e.target.value)}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="agenda-duration">Duration (minutes)</Label>
              <Input
                id="agenda-duration"
                type="number"
                min="1"
                className={fieldClass("duration_minutes")}
                value={draft.duration_minutes}
                onChange={(e) => update("duration_minutes", e.target.value)}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="agenda-participants">Participants</Label>
              <Input
                id="agenda-participants"
                type="number"
                min="0"
                className={fieldClass("participant_count")}
                value={draft.participant_count}
                onChange={(e) => update("participant_count", e.target.value)}
              />
            </div>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="grid gap-2">
              <Label htmlFor="agenda-items">
                Agenda items (title | minutes | notes)
              </Label>
              <Textarea
                id="agenda-items"
                className={fieldClass("agenda_items")}
                value={draft.agenda_items}
                onChange={(e) => update("agenda_items", e.target.value)}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="action-items">
                Action items (description | owner | due date)
              </Label>
              <Textarea
                id="action-items"
                className={fieldClass("action_items")}
                value={draft.action_items}
                onChange={(e) => update("action_items", e.target.value)}
              />
            </div>
          </div>
          <Button
            type="button"
            onClick={() => save.mutate()}
            disabled={save.isPending || !draft.title || !draft.start_at}
          >
            {save.isPending ? "Saving…" : "Save reviewed agenda"}
          </Button>
        </CardContent>
      </Card>

      <section className="grid gap-3">
        <h2 className="font-heading text-xl font-semibold">Saved meetings</h2>
        {meetings.data?.meetings.map((meeting) => (
          <Card key={meeting.id}>
            <CardContent className="flex items-start justify-between gap-4 py-4">
              <div>
                <p className="font-medium">{meeting.title}</p>
                <p className="text-sm text-muted-foreground">
                  {new Date(meeting.start_at).toLocaleString()} ·{" "}
                  {meeting.duration_minutes} min · {meeting.participant_count}{" "}
                  participants
                </p>
              </div>
              {meeting.ai_model && (
                <Badge variant="outline">Suggested by Nova</Badge>
              )}
            </CardContent>
          </Card>
        ))}
      </section>
    </div>
  );
}
