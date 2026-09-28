"""Typed readiness proposal and bounded observation surface."""

from typing import Literal, Protocol

from pydantic import BaseModel, ConfigDict, Field, model_validator

View = Literal["manifest", "events", "logs", "work"]


class Decision(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)
    action: Literal["repair", "wait", "abstain"]
    observation_id: str | None = Field(default=None, max_length=64)
    revision: str | None = Field(default=None, pattern=r"^[a-f0-9]{40}$")
    readiness_path: Literal["/health", "/ready", "/missing"] | None = None
    liveness_path: Literal["/health", "/live", "/missing"] | None = None
    rationale: str = Field(min_length=1, max_length=1500)

    @model_validator(mode="after")
    def validate_action(self):
        if self.action != "abstain" and (not self.observation_id or not self.revision):
            raise ValueError("A current observation and revision are required")
        paths = (self.readiness_path, self.liveness_path)
        if self.action == "repair" and any(p is None for p in paths):
            raise ValueError("Repair requires both explicit probe routes")
        if self.action != "repair" and any(p is not None for p in paths):
            raise ValueError("Only repair can include probe changes")
        return self


class Observer(Protocol):
    async def observe(self, view: View) -> dict: ...
