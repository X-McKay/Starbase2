"""Strict package data, independent of checkout location or enterprise services."""

import hashlib
from importlib.resources import files
from typing import Literal, cast

from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic_ai.settings import ModelSettings as PydanticModelSettings


class FrozenDefinition(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)


class MissionPolicy(FrozenDefinition):
    version: Literal["readiness-mission-v1"]
    target: Literal["owned-lab/readiness-lab/readiness-fixture"]
    model_requests: int = Field(gt=0)
    total_tokens: int = Field(gt=0)
    output_tokens_per_request: int = Field(gt=0)
    tool_calls: int = Field(gt=0)
    tool_result_bytes: int = Field(gt=0)
    mission_seconds: int = Field(gt=0)
    evidence_seconds: int = Field(gt=0)
    mutations: Literal[1]
    memory: None
    xp: Literal[0]


class ChatTemplate(FrozenDefinition):
    enable_thinking: Literal[False]


class ExtraBody(FrozenDefinition):
    chat_template_kwargs: ChatTemplate


class ModelConfiguration(FrozenDefinition):
    temperature: float = Field(ge=0, le=0, allow_inf_nan=False)
    max_tokens: int = Field(gt=0)
    parallel_tool_calls: Literal[False]
    tool_choice: Literal["auto"]
    extra_body: ExtraBody


class ProviderProfile(FrozenDefinition):
    openai_supports_tool_choice_required: Literal[False]


class AgentDefinition(FrozenDefinition):
    contract_version: Literal[1]
    name: Literal["readiness_crew_v1"]
    version: str = Field(pattern=r"^\d+\.\d+\.\d+$")
    authority: Literal["owned-lab-observation-and-proposal"]
    instructions: Literal["instructions.md"]
    tools: tuple[
        Literal["inspect_workload"],
        Literal["inspect_events"],
        Literal["inspect_logs"],
        Literal["check_useful_work"],
    ]
    tool_effect: Literal["read"]
    tool_retry_safety: Literal["safe"]
    tool_timeout: None
    timeout_owner: Literal["mission-deadline-and-adapter-command"]
    retries: Literal[0]
    end_strategy: Literal["graceful"]
    policy: MissionPolicy
    model_settings: ModelConfiguration
    provider_profile: ProviderProfile

    @model_validator(mode="after")
    def consistent_limits(self):
        if self.model_settings.max_tokens != self.policy.output_tokens_per_request:
            raise ValueError("Model output bound differs from mission policy")
        if self.policy.total_tokens < self.policy.output_tokens_per_request:
            raise ValueError("Total token budget cannot cover one output")
        if self.policy.evidence_seconds > self.policy.mission_seconds:
            raise ValueError("Evidence cannot outlive mission authority")
        return self


def load_definition() -> AgentDefinition:
    return AgentDefinition.model_validate_json(resource_bytes("agent.json"))


def resource_bytes(name: str) -> bytes:
    content = files(__package__).joinpath(name).read_bytes()
    expected = globals().get("_RESOURCE_HASHES", {}).get(name)
    if expected is not None and hashlib.sha256(content).hexdigest() != expected:
        raise ValueError("Readiness package changed after import; load a new immutable build")
    return content


def procedure(variant: str) -> dict | None:
    if variant == "baseline":
        return None
    if variant != "runbook-v1":
        raise ValueError("Unknown immutable readiness variant")
    content = resource_bytes("runbooks/readiness-v1.md")
    return {
        "name": "readiness-diagnosis",
        "version": 1,
        "content": content.decode(),
        "sha256": hashlib.sha256(content).hexdigest(),
    }


def instructions(variant: str) -> str:
    spec = load_definition()
    prompt = resource_bytes(spec.instructions).decode()
    item = procedure(variant)
    return prompt if item is None else prompt + "\nRun book Procedure:\n" + item["content"]


# Legacy coordinator imports remain stable. These represent the admitted package;
# changing the package requires a new process/build, never a live policy reload.
DEFINITION = load_definition()
POLICY = DEFINITION.policy.model_dump()
MODEL_SETTINGS = cast(PydanticModelSettings, DEFINITION.model_settings.model_dump(mode="json"))
PROVIDER_PROFILE = DEFINITION.provider_profile.model_dump()
PROMPT = resource_bytes(DEFINITION.instructions).decode()
_RESOURCE_HASHES = {
    name: hashlib.sha256(resource_bytes(name)).hexdigest()
    for name in ("agent.json", "instructions.md", "runbooks/readiness-v1.md")
}
