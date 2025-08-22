using Microsoft.AspNetCore.Mvc;
using Mood.API.Services;

[ApiController]
[Route("api/[controller]")]
public class NudgeController : ControllerBase
{
    private readonly AIService _aiService;

    public NudgeController(AIService aiService)
    {
        _aiService = aiService;
    }

    [HttpPost("mood")]
    public async Task<IActionResult> GetMoodNudges([FromBody] MoodRequest request)
    {
        // Ask AI to generate 10 short conversation topics in the same language as the mood
        var prompt = $"Generate 20 short conversation topics for couples to bring each other closer when feeling '{request.Mood}'. " +
                     $"Each topic should be one line, only the topic, nothing else just plain enumerated topics. Response must be in the language from the mood word received.";

        var topics = await _aiService.GenerateText(prompt);

        // Clean each topic from quotes and empty lines
        var cleanedTopics = topics
            .Select(t => t.Trim().Trim('"'))
            .Where(t => !string.IsNullOrWhiteSpace(t))
            .Take(10) // ensure max 10 topics
            .ToList();

        if (!cleanedTopics.Any())
        {
            cleanedTopics.Add("No topics generated");
        }

        return Ok(new { Topics = cleanedTopics });
    }
}

public class MoodRequest
{
    public string Mood { get; set; } = string.Empty;
}
