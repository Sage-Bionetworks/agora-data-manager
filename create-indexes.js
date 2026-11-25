db = db.getSiblingDB('agora')

// An import builds its indexes on the staging collections, which are then
// renamed over the live collections, so the suffix is set to '_staging'.
// Defaults to the live collection names when run by hand.
const suffix = process.env.COLLECTION_SUFFIX || '';

print('');
print('Creating indexes for "' + db.getName() + '"');
if (suffix) {
    print('Targeting collections with the "' + suffix + '" suffix');
}
print('');

const collation = { locale: 'en', strength: 2 };

const collections = [
    {
        name: 'geneinfo',
        indexes: [
            { ensembl_gene_id: 1, hgnc_symbol: 1 },
            { hgnc_symbol: 1 },
            { alias: 1 },
            { total_nominations: -1, hgnc_symbol: 1 }
        ],
        collatedIndexes: [
            { hgnc_symbol: 1, ensembl_gene_id: 1 }
        ]
    },
    {
        name: 'genes',
        indexes: [
            { ensembl_gene_id: 1, tissue: 1, model: 1 },
        ],
        collatedIndexes: [
            { hgnc_symbol: 1, tissue: 1, model: 1 }
        ]
    },
    {
        name: 'geneslinks',
        indexes: [
            { geneA_ensembl_gene_id: 1, geneB_ensembl_gene_id: 1 },
            { geneB_ensembl_gene_id: 1 },
        ]
    },
    {
        name: 'genesneuropathcorr',
        indexes: [
            { ensg: 1 }
        ]
    },
    {
        name: 'genesoverallscores',
        indexes: [
            { ensembl_gene_id: 1 }
        ]
    },
    {
        name: 'genesmetabolomics',
        indexes: [
            { ensembl_gene_id: 1 }
        ]
    },
    {
        name: 'genesproteomics',
        indexes: [
            { ensembl_gene_id: 1 }
        ]
    },
    {
        name: 'proteomicstmt',
        indexes: [
            { ensembl_gene_id: 1 }
        ]
    },
    {
        name: 'proteomicssrm',
        indexes: [
            { ensembl_gene_id: 1 }
        ]
    },
    {
        name: 'genesbiodomains',
        indexes: [
            { ensembl_gene_id: 1 }
        ]
    },
    {
        name: 'nominateddrugs',
        indexes: [
            { common_name: 1 },
            { chembl_id: 1, combined_with: 1 }
        ]
    },
    {
        name: 'nominatedtargets',
        indexes: [
            { ensembl_gene_id: 1 },
            { hgnc_symbol: 1 }
        ]
    },
    {
        name: 'uiconfig',
        indexes: [
            { page: 1 }
        ]
    },
    {
        name: 'druginfo',
        indexes: [
            { chembl_id: 1 }
        ]
    }
];

let results;

for (let collection of collections) {
    const name = collection.name + suffix;
    print('Collection: ' + name);
    for (let index of (collection.indexes || [])) {
        print('Creating index...');
        printjson(index);
        results = db[name].createIndex(index);
        if (results && results.ok === 1) {
            print(results.numIndexesBefore < results.numIndexesAfter ? 'Success!' : 'Index already exists.');
        }
        else {
            print('Failed: ' + results.note ? results.note : 'N/A');
        }
    }
    for (let index of (collection.collatedIndexes || [])) {
        print('Creating collated index...');
        printjson(index);
        results = db[name].createIndex(index, { collation: collation });
        if (results && results.ok === 1) {
            print(results.numIndexesBefore < results.numIndexesAfter ? 'Success!' : 'Index already exists.');
        }
        else {
            print('Failed: ' + results.note ? results.note : 'N/A');
        }
    }
    print('');
}
