#!/usr/bin/perl
# SchemeConnect scraper — fetches the live National Scholarship Portal
# scheme listings and writes them out as schemes.json.
#
# Source: https://scholarships.gov.in/All-Scholarships (public, no login,
# server-rendered HTML — confirmed manually before writing this script).
# NSP splits schemes into three buckets via a POST filter form:
#   - centralscheme  = Central Sector Schemes   (fully centrally funded/run)
#   - sponserscheme  = Centrally Sponsored Schemes (centrally funded, state-administered)
#   - statescheme    = State Schemes            (state funded — OUT OF SCOPE, not scraped)
# Both of the first two are legitimate Central Government schemes and are
# scraped here. "Centrally Sponsored" entries repeat once per state/UT (NSP's
# own accordion groups them by state) — each is kept as its own record tagged
# with that one state, rather than merged, so the app's existing per-state
# matching logic (used for Ishan Uday etc.) applies to them unchanged.
#
# What this CAN reliably keep current: scheme name, ministry/state, application
# open/close dates, verification deadlines, official guidelines PDF link.
# What it CANNOT extract automatically: income caps, category/gender/level
# eligibility rules — those live as prose inside each scheme's PDF, not on
# this listing page. Eligibility-matching rules are maintained separately in
# the app and mapped onto this list by scheme id/name.

use strict;
use warnings;
use HTML::Entities ();
use JSON::PP ();

my $BASE_URL = "https://scholarships.gov.in";
my $OUT_DIR = ".";
my $OUT_JSON = "$OUT_DIR/schemes_live.json";

my @BUCKETS = (
    { key => 'centralscheme', label => 'central_sector',      raw => "$OUT_DIR/_nsp_central.html" },
    { key => 'sponserscheme', label => 'centrally_sponsored', raw => "$OUT_DIR/_nsp_sponsored.html" },
);

sub fetch_bucket {
    my ($bucket) = @_;
    my $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) SchemeConnect-Scraper/1.0 (+educational capstone project)";
    if ($bucket->{key} eq 'centralscheme') {
        # first page load, no filter needed — matches the default view
        my $cmd = qq{curl -s -L "$BASE_URL/All-Scholarships" -A "$ua" --max-time 30 -o "$bucket->{raw}" -w "%{http_code}"};
        my $code = `$cmd`;
        die "Fetch failed for $bucket->{key}, HTTP $code\n" unless $code eq "200";
    } else {
        my $cmd = qq{curl -s -X POST "$BASE_URL/centralsOrsponsoredOrstate" }
                . qq{-A "$ua" -H "Content-Type: application/x-www-form-urlencoded" }
                . qq{-H "Referer: $BASE_URL/All-Scholarships" }
                . qq{--data "central_sponsored_state=$bucket->{key}" }
                . qq{-L --max-time 30 -o "$bucket->{raw}" -w "%{http_code}"};
        my $code = `$cmd`;
        die "Fetch failed for $bucket->{key}, HTTP $code\n" unless $code eq "200";
    }
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
    my $s = shift // '';
    if ($s =~ /(\d{2})-(\d{2})-(\d{4})/) {
        return "$3-$2-$1";
    }
    return undef;
}

my @schemes;
my $slug_seen = {};

for my $bucket (@BUCKETS) {
    fetch_bucket($bucket);
    my $html = slurp($bucket->{raw});

    my @groupBlocks = split /<div class="accordion-item">/, $html;
    shift @groupBlocks; # discard preamble before first group

    for my $block (@groupBlocks) {
        my ($groupName) = $block =~ /accordion-button collapsed"[^>]*>\s*([^<]+?)\s*<\/button>/s;
        $groupName = clean($groupName // 'Unknown');

        my @rows = split /<div class="row mb-4 border-1 border-bottom">/, $block;
        shift @rows;

        for my $row (@rows) {
            my ($name) = $row =~ /<h6>\s*(.*?)\s*<\/h6>/s;
            next unless $name;
            $name = clean($name);

            my ($openStr)  = $row =~ /Scheme\s*Open from\s*(?:\([^)]*\))?\s*:?\s*([\d-]{10})/;
            my ($closeStr) = $row =~ /Student Application\s*Open till\s*(?:\([^)]*\))?\s*:?\s*([\d-]{10})/;
            my $isRenewal  = ($row =~ /Student Application\s*Open till\s*\(for Renewal\)/) ? 1 : 0;
            my ($guideUrl) = $row =~ /<a href="([^"]+)"[^>]*>\s*Specifications\s*<\/a>/;

            my $status = 'open';
            if ($row =~ /Student Application\s*:\s*NOT YET OPENED/) {
                $status = 'not_yet_opened';
            } elsif ($row =~ /Student Application[^:]*:\s*CLOSED/i) {
                $status = 'closed';
            } elsif (!$closeStr) {
                $status = 'unknown';
            }

            my $slug = lc("$bucket->{label}-$name");
            $slug =~ s/[^a-z0-9]+/-/g;
            $slug =~ s/^-+|-+$//g;
            $slug =~ s/-{2,}/-/g;
            if ($slug_seen->{$slug}) {
                $slug_seen->{$slug}++;
                $slug = "$slug-" . $slug_seen->{$slug};
            } else {
                $slug_seen->{$slug} = 1;
            }

            my %record = (
                id               => $slug,
                name             => $name,
                schemeType       => $bucket->{label}, # central_sector | centrally_sponsored
                applicationOpen  => parse_date($openStr),
                applicationClose => parse_date($closeStr),
                status           => $status,
                renewalWindow    => $isRenewal ? JSON::PP::true : JSON::PP::false,
                guidelinesUrl    => $guideUrl,
                officialDomain   => "scholarships.gov.in",
            );

            if ($bucket->{label} eq 'central_sector') {
                $record{ministry} = $groupName;
                $record{states} = undef; # national — no state restriction
            } else {
                my $stateName = $groupName;
                $stateName =~ s/^(State of|UT of)\s+//i;
                $record{ministry} = undef;
                $record{states} = [$stateName]; # this record applies to exactly this state/UT
            }

            push @schemes, \%record;
        }
    }
}

my $json = JSON::PP->new->canonical->pretty->encode({
    source      => "$BASE_URL/All-Scholarships",
    scope       => "Central Sector + Centrally Sponsored schemes only (State Schemes excluded - out of pilot scope)",
    scrapedAt   => scalar(gmtime()) . " UTC",
    schemeCount => scalar(@schemes),
    schemes     => \@schemes,
});

open(my $oh, ">:encoding(UTF-8)", $OUT_JSON) or die $!;
print $oh $json;
close $oh;

my %byType;
$byType{$_->{schemeType}}++ for @schemes;
print "Scraped " . scalar(@schemes) . " schemes -> $OUT_JSON\n";
print "  $_: $byType{$_}\n" for sort keys %byType;
