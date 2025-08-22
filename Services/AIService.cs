using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Mood.API.Services
{
    public class AIService
    {
        private readonly HttpClient _httpClient;
        private readonly IConfiguration _config;

        public AIService(HttpClient httpClient, IConfiguration config)
        {
            _httpClient = httpClient;
            _config = config;

            // Base URL for Mistral AI
            _httpClient.BaseAddress = new Uri("https://api.mistral.ai/v1/");

            var apiKey = _config["MistralKey"];
            if (string.IsNullOrWhiteSpace(apiKey))
                throw new ArgumentException("Mistral API key is not set in configuration.");

            _httpClient.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", apiKey);
        }

        public async Task<List<string>> GenerateText(string prompt)
        {
            var requestBody = new
            {
                model = "mistral-small-latest", // You can use mistral-medium, mistral-large
                messages = new[]
                {
                    new { role = "user", content = prompt }
                },
                max_tokens = 150,
            };

            var response = await _httpClient.PostAsync(
                "chat/completions",
                new StringContent(JsonSerializer.Serialize(requestBody), Encoding.UTF8, "application/json")
            );

            response.EnsureSuccessStatusCode();

            var responseBody = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(responseBody);
            var content = doc.RootElement
                .GetProperty("choices")[0]
                .GetProperty("message")
                .GetProperty("content")
                .GetString();

            return content?.Split('\n').Where(s => !string.IsNullOrWhiteSpace(s)).ToList() ?? new List<string>();
        }
    }
}
