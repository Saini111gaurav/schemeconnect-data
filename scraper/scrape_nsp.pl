#!/usr/bin/perl
# SchemeConnect scraper — fetches the live National Scholarship Portal
# scheme listing and writes it out as schemes.json.
#
# Source: https://scholarships.gov.in/All-Scholarships (public, no login,
# server-rendered HTML — confirmed manually before writing this script).
#
# What this CAN reliably keep current: scheme name, ministry, application
# open/close dates, verification deadlines, official guidelines PDF link.
# What it CANNOT extract automatically: income caps, category/gender/level
# eligibility rules — those live as prose inside each scheme's PDF, not on
# this listing page. See eligibility_overrides.json for how that's handled.

use strict;
use warnings;
use HTML::Entities ();
use JSON::PP ();

my $SOURCE_URL = "https://scholarships.gov.in/All-Scholarships";
my $OUT_DIR = ".";
my $RAW_HTML = "$OUT_DIR/_nsp_raw.html";
my $OUT_JSON = "$OUT_DIR/schemes_live.json";

sub fetch {
    my $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) SchemeConnect-Scraper/1.0 (+educational capstone project)";
    my $cmd = qq{curl -s -L "$SOURCE_URL" -A "$ua" --max-time 30 -o "$RAW_HTML" -w "%{http_code}"};
    my $code = `$cmd`;
    die "Fetch failed, HTTP $code\n" unless $code eq "200";
    return;
}

sub slurp {
    open(my $fh, "<:encoding(UTF-8)", $_[0]) or die "$_[0]: $!";
    local $/;
    my $c = <$fh>;
    close $fh;
    return $c;
}

sub clean {
    my $s = shift // '';
    $s = HTML::Entities::decode_entities($s);
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    return $s;
}

sub parse_date {
    # NSP dates are dd-mm-yyyy -> convert to yyyy-mm-dd for the app
    my $s = shift // '';
    if ($s =~ /(\d{2})-(\d{2})-(\d{4})/) {
        return "$3-$2-$1";
    }
    return undef;
}

fetch();
my $html = slurp($RAW_HTML);

my @schemes;
my $slug_seen = {};

# Split into accordion-item blocks (one per ministry)
my @ministryBlocks = split /<div class="accordion-item">/, $html;
shift @ministryBlocks; # discard preamble before first ministry

for my $block (@ministryBlocks) {
    my ($ministry) = $block =~ /accordion-button collapsed"[^>]*>\s*([^<]+?)\s*<\/button>/s;
    $ministry = clean($ministry // 'Unknown Ministry');

    # Each scheme is a "row mb-4 border-1 border-bottom" div containing an <h6> name
    my @rows = split /<div class="row mb-4 border-1 border-bottom">/, $block;
    shift @rows;

    for my $row (@rows) {
        my ($name) = $row =~ /<h6>\s*(.*?)\s*<\/h6>/s;
        next unless $name;
        $name = clean($name);

        my ($openStr)  = $row =~ /Scheme\s*Open from\s*(?:\([^)]*\))?\s*:?\s*([\d-]{10})/;
        my ($closeStr) = $row =~ /Student Application\s*Open till\s*(?:\([^)]*\))?\s*:?\s*([\d-]{10})/;
        my ($isRenewal) = $row =~ /Student Application\s*Open till\s*\(for Renewal\)/ ? 1 : 0;
        my ($guideUrl) = $row =~ /<a href="([^"]+)"[^>]*>\s*Specifications\s*<\/a>/;

        my $status = 'open';
        if ($row =~ /Student Application\s*:\s*NOT YET OPENED/) {
            $status = 'not_yet_opened';
        } elsif ($row =~ /Student Application[^:]*:\s*CLOSED/i) {
            $status = 'closed';
        } elsif (!$closeStr) {
            $status = 'unknown';
        }

        my $slug = lc($name);
        $slug =~ s/[^a-z0-9]+/-/g;
        $slug =~ s/^-+|-+$//g;
        $slug =~ s/-{2,}/-/g;
        if ($slug_seen->{$slug}) {
            $slug_seen->{$slug}++;
            $slug = "$slug-" . $slug_seen->{$slug};
        } else {
            $slug_seen->{$slug} = 1;
        }

        push @schemes, {
            id             => $slug,
            name           => $name,
            ministry       => $ministry,
            applicationOpen  => parse_date($openStr),
            applicationClose => parse_date($closeStr),
            status         => $status,
            renewalWindow  => $isRenewal ? JSON::PP::true : JSON::PP::false,
            guidelinesUrl  => $guideUrl,
            officialDomain => "scholarships.gov.in",
            scrapedAt      => scalar gmtime() . " UTC",
        };
    }
}

my $json = JSON::PP->new->canonical->pretty->encode({
    source     => $SOURCE_URL,
    scrapedAt  => scalar gmtime() . " UTC",
    schemeCount => scalar(@schemes),
    schemes    => \@schemes,
});

open(my $oh, ">:encoding(UTF-8)", $OUT_JSON) or die $!;
print $oh $json;
close $oh;

print "Scraped " . scalar(@schemes) . " schemes -> $OUT_JSON\n";
