# Install required packages if not already installed
if(!require(httr2)){install.packages("httr2")}
if(!require(digest)){install.packages("digest")}
if(!require(lubridate)){install.packages("lubridate")}
if(!require(tidyRSS)){install.packages("tidyRSS")}
if(!require(googlesheets4)){install.packages("googlesheets4")}
if(!require(emayili)){install.packages("emayili")}
if(!require(markdown)){install.packages("markdown")}
if(!require(dotenv)){install.packages("dotenv")}

# --- Configuration ---
library(dotenv)

# Load secrets from environment variables
gemini_api_key <- Sys.getenv("GEMINI_API_KEY")
# email_from <- Sys.getenv("EMAIL_FROM")
# email_to <- Sys.getenv("EMAIL_TO")
# email_password <- Sys.getenv("EMAIL_PASSWORD")
rss_sheet_url <- Sys.getenv("RSS_SHEET_URL")
gemini_api_url <- "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent"

# --- Date and Time Formatting ---

# Get the current time in UTC
current_time_utc <- Sys.time()

# Convert to EST (or any other desired time zone)
current_time_est <- with_tz(current_time_utc, tzone = "America/New_York")

# Format the date as "December 30, 2024"
formatted_date <- format(current_time_est, "%B %d, %Y")

# Extract the hour in 24-hour format (use EST time)
current_hour <- as.numeric(format(current_time_est, "%H"))

# Determine the dateline based on the time of day
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

rss_sheet_name_sections <- Sys.getenv("RSS_SHEET_NAME_SECTIONS", "Sections")
rss_sheet_name_feeds <- Sys.getenv("RSS_SHEET_NAME_FEEDS", "Feeds")
rss_sheet_name_style <- Sys.getenv("RSS_SHEET_NAME_STYLE", "Style") 

gs4_deauth()

sections_data <- get_google_sheet_data(rss_sheet_url, sheet_name = rss_sheet_name_sections)
feeds_data <- get_google_sheet_data(rss_sheet_url, sheet_name = rss_sheet_name_feeds)
style_data <- get_google_sheet_data(rss_sheet_url, sheet_name = rss_sheet_name_style)

# Check if style_data was fetched correctly
if (is.null(style_data) || nrow(style_data) == 0) {
  stop("Error: Could not retrieve style data from the Google Sheet.")
}

# Extract style and structure prompts
style_prompt <- paste(style_data[[1]][!is.na(style_data[[1]])], collapse = ".")
structure_prompt <- paste(style_data[[2]][!is.na(style_data[[2]])], collapse = ".")
headline_prompt <- paste(style_data[[3]][!is.na(style_data[[3]])], collapse = ".")

# Construct the system prompt using the style and structure prompts
system_prompt <- paste(
  "You are a helpful assistant curating and summarizing daily news for a newsletter.",
  "Focus ONLY on the following section and provide a direct, concise, conversational summary suitable for a newsletter.",
  "Do not include a header for the section.",
  style_prompt,  # Add the style prompt
  "Here is the desired structure for the newsletter:",
  structure_prompt,  # Add the structure prompt
  "If a section has no new items, state no updates."
)

headline_prompt <-  paste0("You are a helpful assistant curating and summarizing daily news for a newsletter. 
                           The newsletter has sections, each concise, informative, and engaging. 
                           Create a headline that summarizes the most important topics accross all of the sections.
                           The headline should use this style and structure:",
                           headline_prompt,
                           "Here is the newsletter content:")
                          

cache_file <- "guids.csv"

# Load cache from file if it exists
if (file.exists(cache_file)) {
  cache_data <- read.csv(cache_file)
} else {
  cache_data <- data.frame(GUID = character())
}

# Ensure cache_data is a data frame with a "GUID" column
if (!("GUID" %in% names(cache_data))) {
  cache_data <- data.frame(GUID = character())
}


# Initialize newsletter content and final_newsletter_content
newsletter_content <- list()
final_newsletter_content <- ""
cache_empty <- ifelse(nrow(cache_data)==0, TRUE,FALSE)

# --- RSS Feed Processing and Caching ---
for (i in 1:nrow(sections_data)) {  # Process in order from sections_data
  section_name <- sections_data[[1]][i]
  section_prompt <- sections_data[[2]][i]
  section_items <- list()
  
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
        if ("entry_title" %in% names(feed)) {  # Check if it's a Reddit feed
          # Reddit Feed Handling
          for (k in 1:nrow(feed)) {
            item <- feed[k,]
            
            item_title <- item$entry_title
            item_description <- item$entry_content
            item_link <- item$entry_link
            item_date_published <- as.POSIXct(item$entry_published)
            
            item_guid <- digest(paste0(item_link,'-',item_date_published), algo = "sha256")
            
            # Correctly apply the 48-hour filter only if the cache is empty
            if (!(item_guid %in% cache_data$GUID)) {
              if (cache_empty==TRUE) { # Cache is empty
                if (item_date_published >= (Sys.time() - as.difftime(48, units = "hours"))) {
                  # Process item (within last 48 hours)
                  item_content <- if (!is.na(feed_prompt) && feed_prompt != "") {
                    paste(feed_prompt, item_title, item_description)
                  } else {
                    paste(item_title, item_description)
                  }
                  
                  if (item_content != "") {
                    section_items <- c(section_items, list(list(title = item_title, content = item_content, link = item_link)))
                    cache_data <- rbind(cache_data, data.frame(GUID = item_guid))
                  }
                }
              } else { # Cache is not empty, process all items
                item_content <- if (!is.na(feed_prompt) && feed_prompt != "") {
                  paste(feed_prompt, item_title, item_description)
                } else {
                  paste(item_title, item_description)
                }
                
                if (item_content != "") {
                  section_items <- c(section_items, list(list(title = item_title, content = item_content, link = item_link)))
                  cache_data <- rbind(cache_data, data.frame(GUID = item_guid))

                }
              }
            }
          }
        } else if (nrow(feed) > 0) {  # Assume it's a regular RSS feed
          # Regular RSS Feed Handling
          for (k in 1:nrow(feed)) {
            item <- feed[k,]
            
            item_title <- item$item_title
            item_description <- item$item_description
            item_link <- item$item_link
            item_date_published <- as.POSIXct(item$item_pub_date)
            
            item_guid <- digest(paste0(item_link,'-',item_date_published), algo = "sha256")
            
            # Correctly apply the 48-hour filter only if the cache is empty
            if (!(item_guid %in% cache_data$GUID)) {
              if (cache_empty==TRUE) {  # Cache is empty
                if (item_date_published >= (Sys.time() - as.difftime(48, units = "hours"))) {
                  # Process item (within last 48 hours)
                  item_content <- if (!is.na(feed_prompt) && feed_prompt != "") {
                      paste(feed_prompt, item_title, item_description)
                        } else {
                    paste(item_title, item_description)
                  }
                  
                  if (item_content != "") {
                    section_items <- c(section_items, list(list(title = item_title, content = item_content, link = item_link)))
                    cache_data <- rbind(cache_data, data.frame(GUID = item_guid))

                  }
                }
              } else {  # Cache is not empty, process all items
                item_content <- if (!is.na(feed_prompt) && feed_prompt != "") {
                  paste(feed_prompt, item_title, item_description)
                } else {
                  paste(item_title, item_description)
                }
                
                if (item_content != "") {
                  section_items <- c(section_items, list(list(title = item_title, content = item_content, link = item_link)))
                  cache_data <- rbind(cache_data, data.frame(GUID = item_guid))
                }
              }
            }
          }
        } else {
          message("Unknown feed type or empty feed: ", feed_url)
        }
        
      }, error = function(e) {
        message(paste("Error with feed:", feed_url, "Error:", e$message))
      })
    }
  }
  
  # --- Gemini 1.5 Flash API Interaction ---
  if (length(section_items) > 0) {
    # Combine items for each section, including links:
    combined_items_text <- paste(sapply(section_items, function(item) paste0(item$title, ": ", item$content, " (", item$link, ")")), collapse = "\n\n")
    
    # Create a section-specific prompt:
    section_specific_prompt <- paste0(
      system_prompt,
      "Section Name: ", section_name, "\n",
      "Section Instructions: ", section_prompt, "\n\n",
      "Here is the information for this section:\n",
      combined_items_text
    )
    
    tryCatch({
      gemini_request <- request(gemini_api_url) %>%
        req_headers("Content-Type" = "application/json") %>%
        req_body_json(list(
          contents = list(
            parts = list(list(text = section_specific_prompt))
          ),
          # Add safety settings and generation config (optional but recommended)
          safety_settings = list(
            # ... (add your safety settings)
          ),
          generation_config = list(
            temperature = 1  # Adjust as needed
          )
        )) %>%
        req_url_query("key" = gemini_api_key)
      
      gemini_response <- gemini_request %>%
        req_perform() %>%
        resp_body_json()
      
      summarized_text <- gemini_response$candidates[[1]]$content$parts[[1]]$text
      newsletter_content[[section_name]] <- paste0("## ", section_name, "\n", summarized_text, "\n\n")
      message(paste0("Processed section: ", section_name))
      
      
    }, error = function(e) {
      message(paste("Gemini API Error, Section:", section_name,  "Error:", e$message))
      newsletter_content[[section_name]] <- paste0("## ", section_name, "\n", "Error summarizing this section.\n\n")
    })
  }
}


# --- Combine sections, generate Headlines, and re-assemble in order ---
all_sections_content <- paste(unlist(newsletter_content), collapse = "\n\n")

# Generate Headlines section
if (nchar(all_sections_content) > 0){
headline_prompt <- paste0(headline_prompt, all_sections_content)

tryCatch({
  gemini_request <- request(gemini_api_url) %>%
    req_headers("Content-Type" = "application/json") %>% 
    req_body_json(list(contents = list(parts = list(list(text = headline_prompt))),generation_config = list(
      temperature = 1,  # Adjust as needed
      max_output_tokens = 200
    ))) %>%  # Simplified
    req_url_query("key" = gemini_api_key)
  
  gemini_response <- gemini_request %>% req_perform() %>% resp_body_json()
  headline_text <- gemini_response$candidates[[1]]$content$parts[[1]]$text
  
  final_newsletter_content <- paste0("# Headlines\n\n", headline_text, "\n\n")
}, error = function(e) {
  message(paste("Headlines Error:", e$message)) # More specific error message
  final_newsletter_content <- "" # Or an error message
})
} else{
  final_newsletter_content <- ""
}

# Assemble final content in section order, adding links
for (section_name in sections_data[[1]]) {
  if (!is.null(newsletter_content[[section_name]])) {
    # Add links to the original articles
    final_newsletter_content <- paste0(final_newsletter_content, newsletter_content[[section_name]]) # Use text with links
  }
}

# --- Newsletter Generation & Email Sending (mostly the same) ---
newsletter_body <- paste0("# ", dateline, "\n\n", "Your Gemini powered newsletter","\n\n",final_newsletter_content)
newsletter_body_html <- markdown::renderMarkdown(text = newsletter_body) # Convert to HTML
message("Newsletter ready to send")

write(newsletter_body, file = "newsletter.md")

# # --- Email Sending with emayili ---
# if (nchar(final_newsletter_content) > 0) {
#   message("Attempting to send email...")
#   tryCatch({
#     message("Creating email object...")
#     email <- emayili::envelope(
#       to = email_to,
#       from = email_from,
#       subject = email_subject
#     ) %>%
#       html(newsletter_body_html)
#     message("Email object created.")
    
#     message("Defining SMTP server...")
#     server <- gmail(username = email_from,
#                     password = email_password)
#     message("SMTP server defined.")
    
#     message("Size of email:")
#     print(object.size(email))
    
#     message("Sending email...")
#     email %>% server()
#     message("Email sent successfully!")
    
#   }, error = function(e) {
#     message(paste("Error sending email:", e$message))
#   })
#   message("Email sending process completed (or errored).")
# } else {
#   message("No content to send in the newsletter.")
# }

# --- Cache Update ---
# Save cache to file
write.csv(cache_data, cache_file, row.names = FALSE)
message("Cache saved to file.")