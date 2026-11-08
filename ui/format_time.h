#pragma once

#include <cstdio>
#include <string>

#include "esphome/core/time.h"

// Days since 1970-01-01 for a civil date (Howard Hinnant's algorithm).
inline long days_from_civil(int y, unsigned m, unsigned d) {
  y -= m <= 2;
  const int era = (y >= 0 ? y : y - 399) / 400;
  const unsigned yoe = static_cast<unsigned>(y - era * 400);
  const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097L + static_cast<long>(doe) - 719468L;
}

// Formats a UTC ISO timestamp as "heute", "gestern" or "vor 3 Tagen".
// Anything else, such as "unknown" or "unavailable", becomes "--".
inline std::string format_clean_time(const std::string &iso, esphome::ESPTime now) {
  int year, month, day, hour, minute, second;
  if (sscanf(iso.c_str(), "%d-%d-%dT%d:%d:%d", &year, &month, &day, &hour, &minute, &second) != 6)
    return "--";

  const time_t epoch = days_from_civil(year, month, day) * 86400L + hour * 3600L + minute * 60L + second;
  esphome::ESPTime local = esphome::ESPTime::from_epoch_local(epoch);

  if (!now.is_valid()) {
    char date_text[8];
    snprintf(date_text, sizeof(date_text), "%02d.%02d.", local.day_of_month, local.month);
    return date_text;
  }

  const long days = days_from_civil(now.year, now.month, now.day_of_month) -
                    days_from_civil(local.year, local.month, local.day_of_month);
  if (days <= 0)
    return "heute";
  if (days == 1)
    return "gestern";
  return "vor " + std::to_string(days) + " Tagen";
}
