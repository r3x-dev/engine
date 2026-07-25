# frozen_string_literal: true

module R3x
  module Client
    # Minimal YouTube transcript fetcher. No gem dependencies beyond httpx and nokogiri
    # which the project already uses. Hits YouTube's innertube API directly.
    # Extracted logic based on: https://github.com/mkon/youtube-transcript-rb
    # clientVersion: Latest Android app version taken from yt-dlp codebase (extractor/youtube/_base.py)
    # to bypass web client restrictions/CAPTCHA. Update from yt-dlp if YouTube blocks requests.
    class YouTubeTranscript
      WATCH_URL = "https://www.youtube.com/watch?v=%<video_id>s"
      INNERTUBE_URL = "https://www.youtube.com/youtubei/v1/player?key=%<api_key>s"
      INNERTUBE_CONTEXT = { "client" => { "clientName" => "ANDROID", "clientVersion" => "21.02.35" } }.freeze

      Snippet = Data.define(:text, :start, :duration)

      def fetch(video_id)
        html = HTTPX.get(format(WATCH_URL, video_id:), headers: { "accept-language" => "en-US" })
                     .raise_for_status.to_s

        api_key = html[/"INNERTUBE_API_KEY":\s*"([a-zA-Z0-9_-]+)"/, 1]
        raise "Could not extract innertube API key for #{video_id}" unless api_key

        player = HTTPX.post(
          format(INNERTUBE_URL, api_key:),
          json: { "context" => INNERTUBE_CONTEXT, "videoId" => video_id },
        ).raise_for_status.json

        tracks = player.dig("captions", "playerCaptionsTracklistRenderer", "captionTracks")
        raise "No captions available for #{video_id}" if tracks.nil? || tracks.empty?

        caption_url = tracks.first["baseUrl"].gsub("&fmt=srv3", "")
        xml = HTTPX.get(caption_url).raise_for_status.to_s

        R3x::GemLoader.require("nokogiri")
        Nokogiri::XML(xml).xpath("//text").filter_map do |el|
          text = CGI.unescapeHTML(el.text).gsub(/<[^>]*>/, "")
          next if text.empty?

          Snippet.new(text:, start: el["start"].to_f, duration: (el["dur"] || "0").to_f)
        end
      end
    end
  end
end
