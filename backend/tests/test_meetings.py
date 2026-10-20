from httpx import AsyncClient

PAYLOAD = {
    "title": "Planning",
    "start_at": "2026-10-21T10:00:00+03:00",
    "duration_minutes": 60,
    "participant_count": 4,
    "agenda_items": [{"title": "Roadmap", "duration_minutes": 20}],
    "action_items": [{"description": "Send notes", "owner": "Sofia"}],
}


async def test_meeting_crud_and_ai_provenance(client: AsyncClient) -> None:
    payload = {
        **PAYLOAD,
        "ai_suggestion": PAYLOAD,
        "ai_model": "us.amazon.nova-micro-v1:0",
        "ai_prompt_version": "agenda-v1",
    }
    created = await client.post("/api/v1/meetings", json=payload)
    assert created.status_code == 201
    body = created.json()
    assert body["ai_suggestion"]["title"] == "Planning"
    assert body["ai_model"] == "us.amazon.nova-micro-v1:0"

    listed = (await client.get("/api/v1/meetings")).json()
    assert listed["total"] == 1
    assert listed["meetings"][0]["agenda_items"][0]["title"] == "Roadmap"

    updated = await client.patch(
        f"/api/v1/meetings/{body['id']}", json={"title": "Reviewed planning"}
    )
    assert updated.json()["title"] == "Reviewed planning"
    assert (await client.delete(f"/api/v1/meetings/{body['id']}")).status_code == 204


async def test_manual_meeting_has_no_ai_provenance(client: AsyncClient) -> None:
    response = await client.post("/api/v1/meetings", json=PAYLOAD)
    assert response.status_code == 201
    assert response.json()["ai_suggestion"] is None


async def test_partial_ai_provenance_rejected(client: AsyncClient) -> None:
    response = await client.post(
        "/api/v1/meetings", json={**PAYLOAD, "ai_model": "us.amazon.nova-micro-v1:0"}
    )
    assert response.status_code == 422


async def test_meetings_require_authentication(anonymous_client: AsyncClient) -> None:
    assert (await anonymous_client.get("/api/v1/meetings")).status_code == 401
