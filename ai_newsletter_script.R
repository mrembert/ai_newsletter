# Install required packages if not already installed
if(!require(httr2)){install.packages("httr2")}
if(!require(blastula)){install.packages("blastula")}
if(!require(digest)){install.packages("digest")}
if(!require(lubridate)){install.packages("lubridate")}
if(!require(feedeR)){install.packages("tidyRSS")}
if(!require(googlesheets4)){install.packages("googlesheets4")}

# --- Configuration ---

# Load secrets from environment variables
gemini_api_key <- Sys.getenv("GEMINI")
email_from <- Sys.getenv("EMAIL_FROM")
email_to <- Sys.getenv("EMAIL_TO")
email_password <- Sys.getenv("EMAIL_PASSWORD")
rss_sheet_url <- Sys.getenv("RSS_SHEET_URL")
gemini_api_url <- "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent"

# Date for newsletter and subject
current_date <- today()
dateline <- paste0("Morning Newsletter - ", current_date)
email_subject <- paste0("Daily Newsletter - ", current_date)

# System Prompt for Newsletter Consistency (updated for headlines)
system_prompt <- "You are a helpful assistant curating and summarizing daily news for a newsletter. The newsletter has sections, each concise, informative, and engaging. Maintain consistent tone and style. Format with clear headings, use markdown, avoid jargon, and explain complex topics accessibly. If a section has no new items, state no updates. You will also create a headline section summarizing the top stories across all sections at the beginning of the newsletter."

# --- Helper Functions ---

# Authenticate with Google Sheets - assumes read/write
#gs4_auth(cache = TRUE) # You may need to set up credentials

get_google_sheet_data <- function(sheet_url, sheet_name) {
  ss <- gs4_get(sheet_url)
  sheet_data <- read_sheet(ss, sheet = sheet_name)
  return(sheet_data)
}

# --- Data Input ---

rss_sheet_name_sections <- Sys.getenv("RSS_SHEET_NAME_SECTIONS", "Sections")
rss_sheet_name_feeds <- Sys.getenv("RSS_SHEET_NAME_FEEDS", "Feeds")

gs4_deauth()

sections_data <- get_google_sheet_data(rss_sheet_url, sheet_name = rss_sheet_name_sections)
feeds_data <- get_google_sheet_data(rss_sheet_url, sheet_name = rss_sheet_name_feeds)

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

# --- RSS Feed Processing and Caching ---
for (i in 1:nrow(sections_data)) {  # Process in order from sections_data
  section_name <- sections_data$Section.Name[i]
  section_prompt <- sections_data$Section.Prompt[i]
  section_items <- list()
  
  # Get feeds for this section
  section_feeds <- feeds_data[feeds_data$Section.Name == section_name, ]
  
  if (nrow(section_feeds) > 0) {
    for (j in 1:nrow(section_feeds)) {
      feed_url <- section_feeds$RSS.Feed.URL[j]
      feed_prompt <- section_feeds$Feed.Prompt[j]
      
      # Fetch and parse RSS feed (with error handling)
      tryCatch({
        feed <- tidyRSS::tidyfeed(feed_url)
        feed <- head(feed,20)
        
        # Reddit vs. Regular RSS Logic
        if ("entry_title" %in% names(feed)) {  # Check if it's a Reddit feed
          # Reddit Feed Handling
          for (k in 1:nrow(feed)) {
            item <- feed[k,]
            
            item_title <- item$entry_title
            item_description <- item$entry_content
            item_link <- item$entry_link
            item_date_published <- as.POSIXct(item$entry_published)
            
            item_guid <- digest(item_link, algo = "sha256")
            
            # Correctly apply the 48-hour filter only if the cache is empty
            if (!(item_guid %in% cache_data$GUID)) {
              if (nrow(cache_data) == 0) { # Cache is empty
                if (item_date_published >= (Sys.time() - as.difftime(48, units = "hours"))) {
                  # Process item (within last 48 hours)
                  item_content <- if (!is.na(feed_prompt) && feed_prompt != "") {
                    if (grepl(feed_prompt, item_title, ignore.case = TRUE) || grepl(feed_prompt, item_description, ignore.case = TRUE)) {
                      paste(item_title, item_description, " [Link]")
                    } else {
                      ""
                    }
                  } else {
                    paste(item_title, item_description, " [Link]")
                  }
                  
                  if (item_content != "") {
                    section_items <- c(section_items, list(list(title = item_title, content = item_content, link = item_link)))
                    cache_data <- rbind(cache_data, data.frame(GUID = item_guid))
                  }
                }
              } else { # Cache is not empty, process all items
                item_content <- if (!is.na(feed_prompt) && feed_prompt != "") {
                  if (grepl(feed_prompt, item_title, ignore.case = TRUE) || grepl(feed_prompt, item_description, ignore.case = TRUE)) {
                    paste(item_title, item_description, " [Link]")
                  } else {
                    ""
                  }
                } else {
                  paste(item_title, item_description, " [Link]")
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
            
            item_guid <- digest(item_link, algo = "sha256")
            
            # Correctly apply the 48-hour filter only if the cache is empty
            if (!(item_guid %in% cache_data$GUID)) {
              if (nrow(cache_data) == 0) {  # Cache is empty
                if (item_date_published >= (Sys.time() - as.difftime(48, units = "hours"))) {
                  # Process item (within last 48 hours)
                  item_content <- if (!is.na(feed_prompt) && feed_prompt != "") {
                    if (grepl(feed_prompt, item_title, ignore.case = TRUE) || grepl(feed_prompt, item_description, ignore.case = TRUE)) {
                      paste(item_title, item_description, " [Link]")
                    } else {
                      ""
                    }
                  } else {
                    paste(item_title, item_description, " [Link]")
                  }
                  
                  if (item_content != "") {
                    section_items <- c(section_items, list(list(title = item_title, content = item_content, link = item_link)))
                    cache_data <- rbind(cache_data, data.frame(GUID = item_guid))
                  }
                }
              } else {  # Cache is not empty, process all items
                item_content <- if (!is.na(feed_prompt) && feed_prompt != "") {
                  if (grepl(feed_prompt, item_title, ignore.case = TRUE) || grepl(feed_prompt, item_description, ignore.case = TRUE)) {
                    paste(item_title, item_description, " [Link]")
                  } else {
                    ""
                  }
                } else {
                  paste(item_title, item_description, " [Link]")
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
      "You are a helpful assistant curating and summarizing daily news for a newsletter. ",
      "Focus ONLY on the following section and provide a direct, concise, conversational summary suitable for a newsletter. ",
      "Do not include any conversational introductory phrases. Use bullets. ",
      "Include a link to the source referenced in your summary. Use this format: If you see \"[Link]\" in the text, create a working Markdown link in the format '[Link](url)'. Do not generate any other links.\n\n",
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
            # ... (other generation parameters)
          )
        )) %>%
        req_url_query("key" = gemini_api_key)
      
      gemini_response <- gemini_request %>%
        req_perform() %>%
        resp_body_json()
      
      summarized_text <- gemini_response$candidates[[1]]$content$parts[[1]]$text
      newsletter_content[[section_name]] <- paste0("## ", section_name, "\n", summarized_text, "\n\n")
      message(paste0("Processed section: ", section_name))
      
      Sys.sleep(10)
      
    }, error = function(e) {
      message(paste("Gemini API Error, Section:", section_name,  "Error:", e$message))
      newsletter_content[[section_name]] <- paste0("## ", section_name, "\n", "Error summarizing this section.\n\n")
    })
  }
}


# --- Combine sections, generate Headlines, and re-assemble in order ---
all_sections_content <- paste(unlist(newsletter_content), collapse = "\n\n")

# Generate Headlines section
headline_prompt <- paste0("You are a helpful assistant curating and summarizing daily news for a newsletter. The newsletter has sections, each concise, informative, and engaging. Maintain consistent tone and style. Format with clear headings, use markdown, avoid jargon, and explain complex topics accessibly.\n\nPlease create a headlines section summarizing the most important information from the following newsletter content. Do not include any conversational introductory phrases or a 'Headlines' header.:\n\n", all_sections_content)

tryCatch({
  gemini_request <- request(gemini_api_url) %>%
    req_headers("Content-Type" = "application/json") %>%
    req_body_json(list(contents = list(parts = list(list(text = headline_prompt))))) %>%  # Simplified
    req_url_query("key" = gemini_api_key)
  
  gemini_response <- gemini_request %>% req_perform() %>% resp_body_json()
  headline_text <- gemini_response$candidates[[1]]$content$parts[[1]]$text
  
  final_newsletter_content <- paste0("# Headlines\n\n", headline_text, "\n\n")
}, error = function(e) {
  message(paste("Headlines Error:", e$message)) # More specific error message
  final_newsletter_content <- "" # Or an error message
})


# Assemble final content in section order, adding links
for (section_name in sections_data$Section.Name) {
  if (!is.null(newsletter_content[[section_name]])) {
    # Add links to the original articles
    final_newsletter_content <- paste0(final_newsletter_content, newsletter_content[[section_name]]) # Use text with links
  }
}

# --- Newsletter Generation & Email Sending (mostly the same) ---
newsletter_body <- paste0("# ", dateline, "\n\n", final_newsletter_content)


# --- Email Sending ---
if (nchar(final_newsletter_content) > 0) { # check if there is actual content to send.
  tryCatch({
    # Create the email message
    email <- blastula::compose_email(
      body = blastula::md(newsletter_body)
    )
    
    # Create a credentials object
    credentials <- blastula::creds_envvar(
      user = email_from,
      pass_envvar = "EMAIL_PASSWORD",
      host = "smtp.gmail.com",
      port = 465,
      use_ssl = TRUE
    )
    
    
    # Send the email using smtp_send with credentials
    blastula::smtp_send(
      email,
      to = email_to,
      from = email_from,
      subject = email_subject,
      credentials = credentials, # Pass in the credentials object
      verbose = TRUE  # Include for debugging
    )
    
    message("Newsletter sent successfully!")
    
  }, error = function(e) {
    message(paste("Error sending email:", e$message))
  })
} else {
  message("No content to send in the newsletter.")
}
# --- Cache Update ---
# Save cache to file
write.csv(cache_data, cache_file, row.names = FALSE)
message("Cache saved to file.")