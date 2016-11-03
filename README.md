# NAME

PsiBlastHelper - It's modulino that splits fasta input file into number of chunks for BLAST, PSI-BLAST and HMMER to run them on cluster or grid

# SYNOPSIS

    # test example
    lib/PsiBlastHelper.pm --infile=t/data/dm_splicvar --out=t/data/dm_chunks/ --chunk_name=dm --chunk_size=140 --fasta_size 3000 --cpu 5 --cpu_l 5 --db_name=dbfull --db_path=/shared/msestak/db_full_plus --db_gz_name=dbfull_plus_format_new.tar.gz

    # possible options for BLAST database
    --db_name=dbfull  --db_path=/shared/msestak/db_full_plus --db_gz_name=dbfull_plus_format_new.tar.gz
    --db_name=db90    --db_path=/shared/msestak/db90_plus    --db_gz_name=db90_plus_format_new.tar.gz
    --db_name=db90old --db_path=/shared/msestak/db90old      --db_gz_name=db90old_format.tar.gz

# DESCRIPTION

PsiBlastHelper is ...

# LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

mocnii <msestak@irb.hr>
