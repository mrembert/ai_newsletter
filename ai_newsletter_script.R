# Install required packages if not already installed
if (!require(httr2)) {
  install.packages("httr2")
}
if (!require(digest)) {
  install.packages("digest")
}
if (!require(lubridate)) {
  install.packages("lubridate")
}
if (!require(tidyRSS)) {
  install.packages("tidyRSS")
}
if (!require(googlesheets4)) {
  install.packages("googlesheets4")
}
if (!require(emayili)) {
  install.packages("emayili")
}
if (!require(markdown)) {
  install.packages("markdown")
}

# --- Configuration ---

# Load secrets from environment variables
gemini_api_key <- Sys.getenv("GEMINI_API_KEY")
email_from <- Sys.getenv("EMAIL_FROM")
email_to <- Sys.getenv("EMAIL_TO")
email_password <- Sys.getenv("EMAIL_PASSWORD")
rss_sheet_url <- Sys.getenv("RSS_SHEET_URL")
gemini_api_url <-
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

# --- Date and Time Formatting ---

# Get the current time in UTC
current_time_utc <- Sys.time()

# Convert to EST
current_time_est <- with_tz(current_time_utc, tzone = "America/New_York")

# Format the date
formatted_date <- format(current_time_est, "%B %d, %Y")

# Extract the hour in 24-hour format
current_hour <- as.numeric(format(current_time_est, "%H"))

# Determine the dateline and email subject based on the time of day
if (current_hour < 12) {
  dateline <- paste0("Good morning on ", formatted_date)
  email_subject <- paste0("Morning Update - ", formatted_date)
} else if (current_hour >= 12 && current_hour < 17) {
  dateline <- paste0("Good afternoon on ", formatted_date)
  email_subject <- paste0("Afternoon Update - ", formatted_date)
} else {
  dateline <- paste0("Good evening on ", formatted_date)
  email_subject <- paste0("Evening Update - ", formatted_date)
}

# --- Helper Functions ---

get_google_sheet_data <- function(sheet_url, sheet_name) {
  ss <- gs4_get(sheet_url)
  sheet_data <- read_sheet(ss, sheet = sheet_name)
  return(sheet_data)
}

# --- Data Input ---

rss_sheet_name_sections <-
  Sys.getenv("RSS_SHEET_NAME_SECTIONS", "Sections")
rss_sheet_name_feeds <- Sys.getenv("RSS_SHEET_NAME_FEEDS", "Feeds")
rss_sheet_name_style <- Sys.getenv("RSS_SHEET_NAME_STYLE", "Style")

gs4_deauth()

sections_data <-
  get_google_sheet_data(rss_sheet_url, sheet_name = rss_sheet_name_sections)
feeds_data <-
  get_google_sheet_data(rss_sheet_url, sheet_name = rss_sheet_name_feeds)
style_data <-
  get_google_sheet_data(rss_sheet_url, sheet_name = rss_sheet_name_style)

# Check if style_data was fetched correctly
if (is.null(style_data) | nrow(style_data) == 0) {
  stop("Error: Could not retrieve style data from the Google Sheet.")
}

# Extract style, structure, and headline prompts
style_prompt <-
  paste(style_data[[1]][!is.na(style_data[[1]])], collapse = ".")
structure_prompt <-
  paste(style_data[[2]][!is.na(style_data[[2]])], collapse = ".")
headline_prompt <-
  paste(style_data[[3]][!is.na(style_data[[3]])], collapse = ".")

# Construct the system prompt
system_prompt <- paste(
  "You are a helpful assistant curating and summarizing daily news for a newsletter.",
  "Focus ONLY on the following section and provide a direct, concise, conversational summary suitable for a newsletter.",
  "Do not include a header for the section.",
  style_prompt,
  "Here is the desired structure for the newsletter:",
  structure_prompt,
  "If a section has no new items, state no updates."
)

headline_prompt <-
  paste0(
    "You are a helpful assistant curating and summarizing daily news for a newsletter.",
    "The newsletter has sections, each concise, informative, and engaging.",
    "Create a headline that summarizes the most important topics accross all of the sections.",
    "The headline should use this style and structure:",
    headline_prompt,
    "Here is the newsletter content:"
  )

cache_file <- "guids.csv"

# Load cache from file if it exists
if (file.exists(cache_file) && file.info(cache_file)$size > 0) {
  cache_data <- read.csv(cache_file)
} else {
  cache_data <- data.frame(GUID = character())
}

# Ensure cache_data is a data frame with a "GUID" column
if (!("GUID" %in% names(cache_data))) {
  cache_data <- data.frame(GUID = character())
}

# Initialize newsletter content
newsletter_content <- list()
final_newsletter_content <- ""

# --- RSS Feed Processing and Caching ---
for (i in 1:nrow(sections_data)) {
  # Process in order from sections_data
  section_name <- sections_data[[1]][i]
  section_prompt <- sections_data[[2]][i]
  section_items <- list()
  feed_items <- list() # Initialize a list to store items for each feed
  
  # Get feeds for this section
  section_feeds <- feeds_data[feeds_data[[1]] == section_name, ]
  
  if (nrow(section_feeds) > 0) {
    for (j in 1:nrow(section_feeds)) {
      feed_url <- section_feeds[[2]][j]
      feed_prompt <- section_feeds[[3]][j]
      
      # Fetch and parse RSS feed (with error handling)
      tryCatch({
        feed <- tidyRSS::tidyfeed(feed_url)
        
        # Reddit vs. Regular RSS Logic
        if ("entry_title" %in% names(feed)) {
          # Check if it's a Reddit feed
          # Rename columns directly without dplyr
          names(feed)[names(feed) == "entry_title"] <- "item_title"
          names(feed)[names(feed) == "entry_content"] <- "item_description"
          names(feed)[names(feed) == "entry_published"] <- "item_pub_date"
          names(feed)[names(feed) == "entry_link"] <- "item_link"
        } 
        
        for (k in 1:nrow(feed)) {
          item <- feed[k, ]
          
          item_title <- item$item_title
          item_description <- item$item_description
          item_link <- item$item_link
          item_date_published <- as.POSIXct(item$item_pub_date)
          
          item_guid <- digest(paste0(item_link, "-", item_date_published), algo = "sha256")
          
          # Check if the item is new or within the last 48 hours if cache is empty
          is_new_item <- !(item_guid %in% cache_data$GUID)
          
          if (is_new_item) {
            # Process item
            item_content <- paste(item_title, item_description) # Combine title and description
            
            # Use feed_url as fallback if feed_prompt is invalid
            if (!is.na(feed_prompt) && feed_prompt != "") {
              grouping_key <- feed_prompt
            } else {
              grouping_key <- feed_url
             }
            
            if (is.null(feed_items[[grouping_key]])) {
              feed_items[[grouping_key]] <- list()
            }
            
            feed_items[[grouping_key]] <- c(feed_items[[grouping_key]], list(list(title = item_title, content = item_content, link = item_link)))
            cache_data <- rbind(cache_data, data.frame(GUID = item_guid))
          }
        }
        
        # --- Structure the Section Content for this feed ---
        if (length(feed_items[[grouping_key]]) > 0) { # Check if this specific feed has items
          section_content_parts <- list() # Moved inside the inner loop
          section_content_parts <- c(section_content_parts, paste("Section prompt:", section_prompt))
          
          # Conditionally add "Feed prompt:" only if it's a valid feed_prompt
          if (!is.na(feed_prompt) && feed_prompt != "" && grouping_key != feed_url) {
            section_content_parts <- c(section_content_parts, paste("Feed prompt:", grouping_key))
          }
          
          for (item in feed_items[[grouping_key]]) {
            section_content_parts <- c(section_content_parts, paste0(item$title, ": ", item$content, " (", item$link, ")"))
          }
          combined_items_text <- paste(section_content_parts, collapse = "\n\n")
          # --- Gemini 1.5 Flash API Interaction ---
          if (nchar(combined_items_text) > 0) {
            # Create a section-specific prompt:
            section_specific_prompt <- paste0(
              system_prompt,
              "Section Name: ", section_name, "\n\n",
              "Here is the information for this section:\n",
              combined_items_text
            )
            
            tryCatch({
              gemini_request <- request(gemini_api_url) %>%
                req_headers("Content-Type" = "application/json") %>%
                req_body_json(list(
                  contents = list(parts = list(list(
                    text = section_specific_prompt
                  ))),
                  safety_settings = list(),
                  generation_config = list(temperature = 1)
                )) %>%
                req_url_query("key" = gemini_api_key)
              
              gemini_response <- gemini_request %>%
                req_perform() %>%
                resp_body_json()
              
              summarized_text <-
                gemini_response$candidates[[1]]$content$parts[[1]]$text
              newsletter_content[[section_name]] <-
                paste0("## ", section_name, "\n", summarized_text, "\n\n")
              message(paste0("Processed section: ", section_name))
              
            }, error = function(e) {
              message(
                paste(
                  "Gemini API Error, Section:",
                  section_name,
                  "Error:",
                  e$message
                )
              )
              newsletter_content[[section_name]] <-
                paste0("## ", section_name, "\n", "Error summarizing this section.\n\n")
            })
          }
        } else {
          message(paste("No new items found for feed:", feed_url, "in section:", section_name))
        }
      }, error = function(e) {
        message(paste("Error with feed:", feed_url, "Error:", e$message))
      })
    }
  } else {
    message(paste("No feeds found for section:", section_name))
  }
  Sys.sleep(5)
}

# --- Combine sections, generate Headlines, and re-assemble in order ---
all_sections_content <-
  paste(unlist(newsletter_content), collapse = "\n\n")

# Generate Headlines section
if (nchar(all_sections_content) > 0) {
  headline_prompt <- paste0(headline_prompt, all_sections_content)
  
  tryCatch({
    gemini_request <- request(gemini_api_url) %>%
      req_headers("Content-Type" = "application/json") %>%
      req_body_json(list(
        contents = list(parts = list(list(text = headline_prompt))),
        generation_config = list(
          temperature = 1,
          max_output_tokens = 200
        )
      )) %>%
      req_url_query("key" = gemini_api_key)
    
    gemini_response <- gemini_request %>%
      req_perform() %>%
      resp_body_json()
    headline_text <-
      gemini_response$candidates[[1]]$content$parts[[1]]$text
    
    final_newsletter_content <-
      paste0("# Headlines\n\n", headline_text, "\n\n")
  }, error = function(e) {
    message(paste("Headlines Error:", e$message))
    final_newsletter_content <- ""
  })
} else {
  final_newsletter_content <- ""
}

# Assemble final content in section order
for (section_name in sections_data[[1]]) {
  if (!is.null(newsletter_content[[section_name]])) {
    final_newsletter_content <-
      paste0(final_newsletter_content, newsletter_content[[section_name]])
  }
}

# --- Newsletter Generation & Email Sending ---
newsletter_body <-
  paste0("# ", dateline, "\n\n", "Your Gemini powered newsletter", "\n\n", final_newsletter_content)
newsletter_body_html <-
  markdown::renderMarkdown(text = newsletter_body)
message("Newsletter ready to send")

write(newsletter_body, file = "newsletter.md")

# --- Email Sending with emayili ---
if (nchar(final_newsletter_content) > 0) {
  message("Attempting to send email...")
  tryCatch({
    message("Creating email object...")
    email <- emayili::envelope(
      to = email_to,
      from = email_from,
      subject = email_subject
    ) %>%
      html(newsletter_body_html)
    message("Email object created.")
    
    message("Defining SMTP server...")
    server <- gmail(username = email_from,
                    password = email_password)
    message("SMTP server defined.")
    
    message("Size of email:")
    print(object.size(email))
    
    message("Sending email...")
    email %>% server()
    message("Email sent successfully!")
    
  }, error = function(e) {
    message(paste("Error sending email:", e$message))
  })
  message("Email sending process completed (or errored).")
} else {
  message("No content to send in the newsletter.")
}

# --- Cache Update ---
write.csv(cache_data, cache_file, row.names = FALSE)
message("Cache saved to file.")
