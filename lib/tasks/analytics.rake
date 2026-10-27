# frozen_string_literal: true

namespace :analytics do
  desc "Backfill survey_daily_metrics from historical raw submissions"
  task backfill: :environment do
    puts "Starting survey_daily_metrics backfill..."

    aggregates = Submission.group(:survey_id, "DATE(submitted_at)").count
    total_processed = 0

    ActiveRecord::Base.transaction do
      aggregates.each do |(survey_id, date_val), count|
        next unless survey_id && date_val

        date = date_val.is_a?(Date) ? date_val : Date.parse(date_val.to_s)

        sql = <<~SQL
          INSERT INTO survey_daily_metrics (survey_id, date, response_count, created_at, updated_at)
          VALUES ($1, $2, $3, NOW(), NOW())
          ON CONFLICT (survey_id, date)
          DO UPDATE SET response_count = $3,
                        updated_at = NOW();
        SQL

        binds = [
          ActiveRecord::Relation::QueryAttribute.new("survey_id", survey_id, ActiveRecord::Type::BigInteger.new),
          ActiveRecord::Relation::QueryAttribute.new("date", date, ActiveRecord::Type::Date.new),
          ActiveRecord::Relation::QueryAttribute.new("response_count", count, ActiveRecord::Type::Integer.new)
        ]

        ActiveRecord::Base.connection.exec_query(sql, "SurveyDailyMetric Backfill", binds)
        total_processed += 1
      end
    end

    puts "Backfill complete. Aggregated #{total_processed} daily metric records."
  end
end
