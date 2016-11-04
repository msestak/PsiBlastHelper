# NAME

PsiBlastHelper - It's modulino that splits fasta input file into number of chunks for BLAST, PSI-BLAST and HMMER to run them on cluster or grid

# SYNOPSIS

    # test example for BLAST and PSI-BLAST
    lib/PsiBlastHelper.pm --infile=t/data/dm_splicvar --out=t/data/dm_chunks/ --chunk_name=dm --chunk_size=1000 --fasta_size 10000 --cpu 5 --cpu_l 5 --db_name=dbfull --db_path=/shared/msestak/db_full_plus --db_gz_name=dbfull_plus_format_new.tar.gz

    # test example for HMMER
    lib/PsiBlastHelper.pm --infile=t/data/dm_splicvar --out=t/data/dm_chunks/ --chunk_name=dm --chunk_size=1000 --fasta_size 10000 --cpu 5 --cpu_l 5 --db_name=dbfull --db_path=/shared/msestak/dbfull --db_gz_name=dbfull.gz

    # possible options for BLAST database
    --db_name=dbfull  --db_path=/shared/msestak/db_full_plus --db_gz_name=dbfull_plus_format_new.tar.gz
    --db_name=db90    --db_path=/shared/msestak/db90_plus    --db_gz_name=db90_plus_format_new.tar.gz
    --db_name=db90old --db_path=/shared/msestak/db90old      --db_gz_name=db90old_format.tar.gz

    # options for HMMER database
    --db_name=dbfull  --db_path=/shared/msestak/dbfull --db_gz_name=dbfull.gz

# DESCRIPTION

PsiBlastHelper is modulino that splits fasta file (input) into a number of chunks for parallel BLAST++, PSI-BLAST or HMMER (default is all of them).
Chunks get short name + different number for each chunk (+ sufix '\_large' if larger than -s or in top N sequences by size).
You need to provide input file, size of the chunk, chunk name and either top n or length of sequences to run separately. 
You also meed provide --cpu or --cpu\_l to split manual SGE or HTCondor on this number of jobs. The idea here is to reduce a number of BLAST database copies (e.g., for every job),
which can lead to failed jobs if out of disk space on specific node.
You can also use -a (--append) to append remainder of sequences to last file or to create new file with this remainder, which is default.
After splitting sequences it also prints SGE and HTCondor jobs bash scripts.
All paths are hardcoded to ISABELLA cluster at tannat.srce.hr and CRO-NGI grid.

For help write:

    perl FastaSplit.pm -h
    perl FastaSplit.pm -m

# LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

mocnii <msestak@irb.hr>
