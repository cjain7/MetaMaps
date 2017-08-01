package validation;

use strict;
use Data::Dumper;
use List::Util qw/all/;
use List::MoreUtils qw/mesh/;
use taxTree;

my @evaluateAccuracyAtLevels = qw/species genus family superkingdom/;
{
	my %_knowRank = map {$_ => 1} taxTree::getRelevantRanks();
	die unless(all {$_knowRank{$_}} @evaluateAccuracyAtLevels);
}

my %_cache_prepare_masterTaxonomy_withX_taxonomies;
sub prepare_masterTaxonomy_withX
{
	my $masterTaxonomy_dir = shift;
	my $taxonomyWithX = shift;

	my $masterTaxonomy;
	if($_cache_prepare_masterTaxonomy_withX_taxonomies{$masterTaxonomy_dir})
	{
		$masterTaxonomy = $_cache_prepare_masterTaxonomy_withX_taxonomies{$masterTaxonomy_dir};
	}
	else
	{
		$masterTaxonomy = taxTree::readTaxonomy($masterTaxonomy_dir);
		$_cache_prepare_masterTaxonomy_withX_taxonomies{$masterTaxonomy_dir} = $masterTaxonomy;
	}
	
	my $masterTaxonomy_merged = taxTree::readMerged($masterTaxonomy_dir);
	
	my $extendedMaster = taxTree::cloneTaxonomy_integrateX($masterTaxonomy, $masterTaxonomy_merged, $taxonomyWithX);

	return ($extendedMaster, $masterTaxonomy_merged);
}

sub readTruthFileReads
{
	my $masterTaxonomy = shift;
	my $masterTaxonomy_merged = shift;
	my $file = shift;
	
	die unless(defined $file);
	my %truth_raw_reads;
	
	open(T, '<', $file) or die "Cannot open $file";
	while(<T>)
	{
		my $line = $_;
		chomp($line);
		next unless($line);
		my @f = split(/\t/, $line);
		my $readID = $f[0];
		my $taxonID_original = $f[1];
		
		# get the taxon ID in the master taxonomy
		my $taxonID_master = taxTree::findCurrentNodeID($masterTaxonomy, $masterTaxonomy_merged, $taxonID_original);
		
		die unless(exists $masterTaxonomy->{$taxonID_master});
		die if(defined $truth_raw_reads{$readID});
		
		$truth_raw_reads{$readID} = $taxonID_master;
	}
	close(T);	
	
	return \%truth_raw_reads;
}

sub translateID2ReducedTaxonomy
{
	my $masterTaxonomy = shift;
	my $reducedTaxonomy = shift;
	my $taxonID = shift;
	
	die unless(defined $taxonID);
	die unless(exists $masterTaxonomy->{$taxonID});
	
	my @nodes_to_consider = ($taxonID, taxTree::get_ancestors($masterTaxonomy, $taxonID));
	
	foreach my $nodeID (@nodes_to_consider)
	{
		if(exists $reducedTaxonomy->{$nodeID})
		{
			return $nodeID;
		}
	}

	checkTaxonomyIsProperReduction();
	
	die "Can't translate taxon $taxonID into the space of reduced taxonomy.";
}

sub translateReadsTruthToReducedTaxonomy
{
	my $masterTaxonomy = shift;
	my $reducedTaxonomy = shift;
	my $reads_href = shift;
	
	checkTaxonomyIsProperReduction();

	my %forReturn_reads;
	my %taxonID_translation;	
	foreach my $readID (keys %$reads_href)
	{
		my $taxonID = $reads_href->{$readID};
		die unless(exists $masterTaxonomy->{$taxonID});
		unless(defined $taxonID_translation{$taxonID})
		{
			$taxonID_translation{$taxonID} = translateID2ReducedTaxonomy($masterTaxonomy, $reducedTaxonomy, $taxonID);
		}
		$forReturn_reads{$readID} = $taxonID_translation{$taxonID};
		die unless(defined $forReturn_reads{$readID});
	}
	
	return \%forReturn_reads;
}

sub checkTaxonomyIsProperReduction
{
	my $masterTaxonomy = shift;
	my $reducedTaxonomy = shift;
	
	
	unless(all {exists $masterTaxonomy->{$_}} keys %$reducedTaxonomy)
	{
		my @missing = grep {not exists $masterTaxonomy->{$_}} keys %$reducedTaxonomy;
		die Dumper("Reduced taxonomy doesn't seem to be a proper subset of full taxonomy!", \@missing);
	}	
}

sub truthReadsToTruthSummary
{
	my $taxonomy = shift;
	my $truthReads_href = shift;
	
	my %taxonID_translation;	
	my %truth_allReads;
	foreach my $readID (keys %$truthReads_href)
	{
		my $taxonID = $truthReads_href->{$readID};
		unless(defined $taxonID_translation{$taxonID})
		{
			$taxonID_translation{$taxonID} = getAllRanksForTaxon_withUnclassified($taxonomy, $taxonID);
		}
		
		foreach my $rank (keys %{$taxonID_translation{$taxonID}})
		{
			my $v = $taxonID_translation{$taxonID}{$rank};
			$truth_allReads{$rank}{$v}++;
		}
		
		foreach my $rank (keys %truth_allReads)
		{
			foreach my $taxonID (keys %{$truth_allReads{$rank}})
			{
				$truth_allReads{$rank}{$taxonID} /= scalar(keys %$truthReads_href);
			}
		}
	}
	
	return \%truth_allReads;
}

sub getAllRanksForTaxon_withUnclassified
{
	my $taxonomy = shift;
	my $taxonID = shift;
	
	die unless(defined $taxonID);
	die unless(defined $taxonomy->{$taxonID});
	
	my %forReturn = map {$_ => 'Unclassified'} @evaluateAccuracyAtLevels;
	
	my @nodes_to_consider = ($taxonID, taxTree::get_ancestors($taxonomy, $taxonID));
	
	my $inTaxonomicAgreement = 0;
	my $firstRankAssigned;
	foreach my $nodeID (@nodes_to_consider)
	{
		my $rank = $taxonomy->{$nodeID}{rank};
		die unless(defined $rank);
		if(exists $forReturn{$rank})
		{
			$forReturn{$rank} = $nodeID;
			$firstRankAssigned = $rank;
		}
	}
		
	
	if(defined $firstRankAssigned)
	{
		my $setToUndefined = 0;
		foreach my $rank (taxTree::getRelevantRanks())
		{
			next unless(exists $forReturn{$rank});
			if($rank eq $firstRankAssigned)
			{
				$setToUndefined = 1;
				die if($forReturn{$rank} eq 'Unclassified');
			}
			else
			{
				if($setToUndefined and ($forReturn{$rank} eq 'Unclassified'))
				{
					$forReturn{$rank} = 'Undefined';
				}
			}
		}
	}		
	
	return \%forReturn;
}

# sub getRank_phylogeny
# {
	# my $fullTaxonomy = shift;
	# my $reducedTaxonomy = shift;
	# my $taxonID = shift;
	
	# my %forReturn = map {$_ => 'Unclassified'} @evaluateAccuracyAtLevels;
	
	# unless(all {exists $fullTaxonomy->{$_}} keys %$reducedTaxonomy)
	# {
		# my @missing = grep {not exists $fullTaxonomy->{$_}} keys %$reducedTaxonomy;
		# die Dumper("Reduced taxonomy doesn't seem to be a proper subset of full taxonomy!", \@missing);
	# }
	# die unless(defined $fullTaxonomy->{$taxonID});
	
	# my @nodes_to_consider = ($taxonID, taxTree::get_ancestors($fullTaxonomy, $taxonID));
	
	# my $inTaxonomicAgreement = 0;
	# my $firstRankAssigned;
	# foreach my $nodeID (@nodes_to_consider)
	# {
		# my $rank = $fullTaxonomy->{$nodeID}{rank};
		# die unless(defined $rank);
		# if(exists $forReturn{$rank})
		# {
			# if(exists $reducedTaxonomy->{$nodeID})
			# {
				# $forReturn{$rank} = $nodeID;
				# $inTaxonomicAgreement = 1;
				# $firstRankAssigned = $rank;
			# }
			# else
			# {
				# $forReturn{$rank} = 'Unclassified';
				# die if($inTaxonomicAgreement);
			# }
		# }
	# }
	
	# if(defined $firstRankAssigned)
	# {
		# my $setToUndefined = 0;
		# foreach my $rank (taxTree::getRelevantRanks())
		# {
			# next unless(exists $forReturn{$rank});
			# if($rank eq $firstRankAssigned)
			# {
				# $setToUndefined = 1;
				# die if($forReturn{$rank} eq 'Unclassified');
			# }
			# else
			# {
				# if($setToUndefined and ($forReturn{$rank} eq 'Unclassified'))
				# {
					# $forReturn{$rank} = 'Undefined';
				# }
			# }
		# }
	# }
	
	# return \%forReturn;
# }


sub readLevelComparison
{
	my $masterTaxonomy = shift;
	my $reads_truth_absolute = shift;
	my $reads_truth_mappingDB = shift;
	my $reads_inferred = shift;
	my $label = shift;
	
	die unless(defined $label);
	
	my @readIDs = keys %$reads_truth_absolute;
	unless((scalar(@readIDs) == scalar(keys %$reads_inferred)) and (all {exists $reads_inferred->{$_}} @readIDs))
	{
		die "Read ID problem - truth and inference sets are not congruent.";
	}
	
	die unless(all {exists $masterTaxonomy->{$_}} values %$reads_truth_absolute);
	die unless(all {exists $masterTaxonomy->{$_}} values %$reads_inferred);

	
	# a 'lightning' is the way from a taxon ID to the top of the tree, and back
	# ... setting levels below the ID to 'unclassified'
	my %_getLightning_cache;
	my $getLightning = sub {
		my $taxonID = shift;
		if(exists $_getLightning_cache{$taxonID})
		{
			return $_getLightning_cache{$taxonID};
		}
		else
		{
			my $lightning = getAllRanksForTaxon_withUnclassified($masterTaxonomy, $taxonID);
			$_getLightning_cache{$taxonID} = $lightning;
			return $lightning;
		}
	};
	
	my $get_read_categories = sub {
		my $readID = shift;
		
		my @categories = ('ALL');
		if($reads_truth_mappingDB->{$readID} eq $reads_truth_absolute->{$readID})
		{
			push(@categories, 'inDB');
		}
		else
		{
			push(@categories, 'novel');
			my $lightning_truth_inDB = $getLightning->($reads_truth_mappingDB->{$readID});
			my $shouldBeAssignedTo;
			foreach my $rank (@evaluateAccuracyAtLevels)
			{
				die unless(defined $lightning_truth_inDB->{$rank});
				if($lightning_truth_inDB->{$rank} ne 'Unclassified')
				{
					$shouldBeAssignedTo = $rank;
				}
			}
			die unless(defined $shouldBeAssignedTo);
			push(@categories, 'novel_to' . $shouldBeAssignedTo);
		}
		return ('ALL');
	};
	
	my %n_reads_correct;
	my %n_reads_correct_byLevel;
	my %taxonID_across_ranks;
	foreach my $readID (@readIDs)
	{
		my $trueTaxonID_inUsedDB = $reads_truth_mappingDB->{$readID};
		my $inferredTaxonID = $reads_truth_mappingDB->{$readID};
		
		my $lightning_truth = $getLightning->($trueTaxonID_inUsedDB);
		my $lightning_inferred = $getLightning->($inferredTaxonID);
		
		my @read_categories = $get_read_categories->($readID);
		foreach my $category (@read_categories)
		{
			unless(defined $n_reads_correct{$category}{N})
			{
				$n_reads_correct{$category}{N} = 0;
				$n_reads_correct{$category}{correct} = 0;
			}
			$n_reads_correct{$category}{N}++;
			if($inferredTaxonID eq $trueTaxonID_inUsedDB)
			{
				$n_reads_correct{$category}{correct}++;
			}
		}
		
		foreach my $level (@evaluateAccuracyAtLevels)
		{
			die unless((defined $lightning_truth->{$level}) and (defined defined $lightning_truth->{$level}));
			foreach my $category (@read_categories)
			{
				unless(defined $n_reads_correct_byLevel{$category}{$level}{N})
				{
					$n_reads_correct_byLevel{$category}{$level}{N} = 0;
					$n_reads_correct_byLevel{$category}{$level}{N_truthDefined} = 0;
					$n_reads_correct_byLevel{$category}{$level}{correct} = 0;
					$n_reads_correct_byLevel{$category}{$level}{correct_truthDefined} = 0;
				}
				
				$n_reads_correct_byLevel{$category}{$level}{N}++;
				$n_reads_correct_byLevel{$category}{$level}{N_truthDefined}++ if($lightning_truth->{$level} ne 'Undefined');
				if($lightning_truth->{$level} eq $lightning_truth->{$level})
				{
					$n_reads_correct_byLevel{$category}{$level}{correct}++;
					$n_reads_correct_byLevel{$category}{$level}{correct_truthDefined}++ if($lightning_truth->{$level} ne 'Undefined');
				}				
			}
		}
	}
	
	foreach my $category (keys %n_reads_correct)
	{
		my $prop_absoluteCorrectness = ($n_reads_correct{$category}{N} > 0) ? ($n_reads_correct{$category}{correct} / $n_reads_correct{$category}{N}) : -1;
		print join("\t", $label, $category, "absoluteCorrectness", $n_reads_correct{$category}{N}, $n_reads_correct{$category}{correct}, sprintf("%.2f", $prop_absoluteCorrectness));
		foreach my $level (@evaluateAccuracyAtLevels)
		{
			my $prop_levelCorrectness = ($n_reads_correct_byLevel{$category}{$level}{N} > 0) ? ($n_reads_correct_byLevel{$category}{$level}{correct} / $n_reads_correct_byLevel{$category}{$level}{N}) : -1;
			print join("\t", $label, $category, $level, $n_reads_correct_byLevel{$category}{$level}{N}, $n_reads_correct_byLevel{$category}{$level}{correct}, sprintf("%.2f", $prop_levelCorrectness));

		}
	}	
}

sub distributionLevelComparison
{	
	my $masterTaxonomy = shift;
	my $distribution_truth = shift;
	my $distribution_inferred = shift;
	my $label = shift;

	foreach my $level (@evaluateAccuracyAtLevels)
	{
		next unless(defined $distribution_inferred->{$level});
		die unless(defined $distribution_truth->{$level});
		my $totalFreq = 0;
		my $totalFreqCorrect = 0;
		foreach my $inferredTaxonID (keys %{$distribution_inferred->{$level}})
		{
			my $isFreq = $distribution_inferred->{$level}{$inferredTaxonID}[1];
			my $shouldBeFreq = 0;
			if(exists $distribution_truth->{$level}{$inferredTaxonID})
			{
				$shouldBeFreq = $distribution_truth->{$level}{$inferredTaxonID};
			}
			
			$totalFreq += $isFreq;
			if($isFreq <= $shouldBeFreq)					
			{
				$totalFreqCorrect += $isFreq;
			}
			else
			{
				$totalFreqCorrect += $shouldBeFreq;
			}
		}
		die Dumper("Weird total freq", $label, $totalFreq, $level) unless(abs(1 - $totalFreq) <= 1e-3);
		
		print join("\t", $label, $level, $totalFreqCorrect), "\n";
	}		
}			
			

sub readInferredDistribution
{
	my $taxonomy = shift;
	my $taxonomy_merged = shift;
	my $f = shift;
	die unless(defined $f);
	
	my %inference;
	open(I, '<', $f) or die "Cannot open $f";
	my $header_line = <I>;
	chomp($header_line);
	my @header_fields = split(/\t/, $header_line);
	while(<I>)
	{
		my $line = $_;
		chomp($line);
		next unless($line);
		my @line_fields = split(/\t/, $line, -1);
		die unless($#line_fields == $#header_fields);
		my %line = (mesh @header_fields, @line_fields);

		my $taxonID_nonMaster = ($line{ID} // $line{taxonID});
		die unless(defined $taxonID_nonMaster);

		next if($line{Name} eq 'TooShort');
		next if($line{Name} eq 'Unmapped');

		if(($taxonID_nonMaster eq '0') and (($line{Name} eq 'Undefined') or ($line{Name} eq 'Unclassified')))
		{
			$taxonID_nonMaster = $line{Name};
		}
		if($taxonID_nonMaster eq '0')
		{
			Dumper($line, $f);
		}

		my $taxonID_master = taxTree::findCurrentNodeID($taxonomy, $taxonomy_merged, $taxonID_nonMaster);
				
		die Dumper(\%line) unless(defined $taxonID_master);
		die Dumper("Unknown taxon ID $taxonID_master in file $f", $taxonomy->{$taxonID_master}) unless(($taxonID_master eq 'Unclassified') or (defined $taxonomy->{$taxonID_master}));
		die unless(defined $line{Absolute});
		die unless(defined $line{PotFrequency});
		$inference{$line{AnalysisLevel}}{$taxonID_master}[0] += $line{Absolute};
		$inference{$line{AnalysisLevel}}{$taxonID_master}[1] += $line{PotFrequency};
	}
	close(I);	
	
	return \%inference;
}

sub readInferredFileReads
{
	my $masterTaxonomy = shift;
	my $masterTaxonomy_merged = shift;
	my $file = shift;
	
	die unless(defined $file);
	my %inferred_raw_reads;
	
	open(I, '<', $file) or die "Cannot open $file";
	while(<I>)
	{
		my $line = $_;
		chomp($line);
		next unless($line);
		my @f = split(/\t/, $line);
		my $readID = $f[0];
		my $taxonID_original = $f[1];
		
		# get the taxon ID in the master taxonomy
		my $taxonID_master = taxTree::findCurrentNodeID($masterTaxonomy, $masterTaxonomy_merged, $taxonID_original);
		
		die unless(exists $masterTaxonomy->{$taxonID_master});
		die if(defined $inferred_raw_reads{$readID});
		
		$inferred_raw_reads{$readID} = $taxonID_master;
	}
	close(I);	
	
	return \%inferred_raw_reads;	
}



1;