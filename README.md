# Daily Newsletter Generator

This repository contains an R script (`newsletter_script.R`) that automatically generates and sends a daily newsletter email. It fetches content from RSS feeds, summarizes it using the Gemini 2.0 Flash API, formats it into a newsletter, and sends it via email using the `blastula` package. The workflow is automated using GitHub Actions.

## Features

*   **Fetches and Parses RSS Feeds:** Supports both standard RSS feeds and Reddit RSS feeds using the `tidyRSS` package.
*   **Content Summarization:** Leverages the Gemini 2.0 Flash API to summarize articles and create a headline section.
*   **Customizable Sections:** Allows you to define different sections for your newsletter (e.g., Technology, Business, Sports) with separate prompts for each section.
*   **Flexible Scheduling:** Sends a "Morning Newsletter" before noon, an "Afternoon Update" between noon and 4 PM, and an "Evening Update" between 5 PM and midnight, all based on the server's local time (defaults to UTC in GitHub Actions).
*   **Markdown Formatting:** Generates links in Markdown format and includes them in the email.
*   **Caching:** Uses GitHub Actions cache to store processed RSS item GUIDs, preventing duplicate content from being included in the newsletter.
*   **Email Sending:** Sends the formatted newsletter via email using the `emayili` package with SMTP authentication.

## Project Structure

*   **`ai_newsletter_script.R`:** The main R script that performs all the tasks.
*   **`.github/workflows/newsletter.yml`:** The GitHub Actions workflow file that automates the script execution.
*   **`guids.csv`:** The cache file used to store processed RSS item GUIDs (managed by GitHub Actions cache).

## Prerequisites

Before you can use this script, you need the following:

*   **A Google Account:** To create a Gemini API Key
*   **A Gemini API Key:**
    *   Go to [Google AI Studio](https://ai.google.dev/) and create a new API key.
    *   Copy the API key.
*   **A GitHub Account:** To host the code and run the GitHub Actions workflow.
*   **An Email Account:** To send the newsletter from (Gmail is recommended and used in this example).

## Setting Up the Project

### 1. Fork the Repository

*   Fork this repository to your own GitHub account by clicking the "Fork" button at the top right of the repository page.

### 2. Configure Google Sheets

*   Create a new Google Sheet with two tabs:
    *   **`Sections`:**
        *   **Column 1:** `Section Name` (e.g., "Technology News", "Market Updates")
        *   **Column 2:** `Section Prompt` (Instructions for Gemini on summarizing this section)
    *   **`Feeds`:**
        *   **Column 1:** `Section Name` (Links the feed to a section in the "Sections" tab)
        *   **Column 2:** `RSS Feed URL`
        *   **Column 3:** `Feed Prompt` (Optional instructions for individual feeds)
*   **Sharing Settings:**
    *   Set the sharing settings of the Google Sheet to "Anyone with the link can view". This allows the script to read the data from the sheet without requiring authentication.

### 3. Set Up GitHub Secrets

*   Go to your forked repository on GitHub.
*   Navigate to **Settings** -> **Secrets** -> **Actions**.
*   Click **New repository secret** and create the following secrets:
    *   **`GEMINI_API_KEY`:** Paste your Gemini API key here.
    *   **`EMAIL_FROM`:** The email address you'll be sending the newsletter from (e.g., your Gmail address).
    *   **`EMAIL_TO`:** The email address where the newsletter will be sent.
    *   **`EMAIL_PASSWORD`:** The password for your email account. **If using Gmail, it is strongly recommended that you create and use an [App Password](https://support.google.com/accounts/answer/185833)** instead of your regular password.
    *   **`RSS_SHEET_URL`:** The shareable link to your Google Sheet (e.g., `https://docs.google.com/spreadsheets/d/YOUR_SHEET_ID/edit?usp=sharing`). Make sure to replace `YOUR_SHEET_ID` with your actual sheet ID.
    *   **`RSS_SHEET_NAME_SECTIONS`:** The name of the "Sections" sheet in your Google Sheet (default: `Sections`).
    *   **`RSS_SHEET_NAME_FEEDS`:** The name of the "Feeds" sheet in your Google Sheet (default: `Feeds`).

### 4. Modify the R Script (Optional)

*   **`newsletter_script.R`:**
    *   **`system_prompt`:** Customize the system prompt to fine-tune the overall tone and style of the newsletter.
    *   **`safety_settings` and `generation_config`:** Modify these parameters in the Gemini API calls to control the safety and creativity of the generated summaries.

### 5. Customize the Workflow Schedule (Optional)

*   **`.github/workflows/newsletter.yml`:**
    *   Modify the `cron` expressions under the `schedule` event to adjust the workflow's execution time. The current settings are:
        *   `0 10 * * *`: 6 AM EDT (Daylight Saving Time)
        *   `0 20 * * *`: 4 PM EDT (Daylight Saving Time)

### 6. Enable GitHub Actions

*   Go to the **Actions** tab in your forked repository.
*   If prompted, enable workflows for your repository.

### 7. Run the Workflow

*   You can manually trigger the workflow by going to the **Actions** tab, selecting the "Daily Newsletter" workflow, and clicking **Run workflow**.
*   The workflow will also run automatically according to the schedule you defined in the `newsletter.yml` file.

### 8. Monitor and Debug

*   Monitor the workflow runs in the **Actions** tab to check for any errors.
*   Examine the logs of each run to troubleshoot issues.
*   If you encounter errors, double-check your script, workflow configuration, and GitHub secrets.

## Troubleshooting

*   **`Error: argument is of length zero` or `Error fetching CSV`:** This usually means the script is unable to fetch data from your Google Sheet. Verify that the sheet is publicly accessible and that the `RSS_SHEET_URL` secret is set correctly. You may need to modify the function `get_google_sheet_data_public()` to correctly construct the URL.
*   **`Gemini API Error`:** If you get an error related to the Gemini API, check the following:
    *   Make sure your `GEMINI_API_KEY` secret is correct.
    *   Verify that the `gemini_api_url` in your script is correct.
    *   Review the Gemini API documentation for any specific error messages.
*   **`Error sending email`:** If you encounter email sending errors:
    *   Double-check your email credentials (`EMAIL_FROM`, `EMAIL_PASSWORD`).
    *   If using Gmail, ensure you are using an App Password.

## Contributing

If you find any issues or want to improve this project, feel free to create an issue or submit a pull request.