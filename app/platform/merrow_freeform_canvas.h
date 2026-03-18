#import <AppKit/AppKit.h>

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
} MerrowFreeformColor;

typedef struct {
    const char * _Nullable id;
    const char * _Nullable label;
    const char * _Nullable parent_subgraph_id;
    uint32_t shape;
    double x;
    double y;
    double width;
    double height;
    MerrowFreeformColor fill;
    MerrowFreeformColor stroke;
    float stroke_width;
    MerrowFreeformColor label_color;
    float label_font_size;
} MerrowFreeformNodeSnapshot;

typedef struct {
    const char * _Nullable source_id;
    const char * _Nullable target_id;
    const char * _Nullable label;
    MerrowFreeformColor color;
    float thickness;
    uint32_t line_style;
    uint8_t has_arrow;
    uint8_t has_source_arrow;
} MerrowFreeformEdgeSnapshot;

typedef struct {
    const char * _Nullable id;
    const char * _Nullable title;
    const char * _Nullable parent_subgraph_id;
    double x;
    double y;
    double width;
    double height;
    double corner_radius;
    MerrowFreeformColor fill;
    MerrowFreeformColor stroke;
    float stroke_width;
    double title_x;
    double title_y;
    float title_font_size;
    MerrowFreeformColor title_color;
} MerrowFreeformSubgraphSnapshot;

typedef struct {
    double width;
    double height;
    uint32_t graph_type;
    MerrowFreeformColor background;
    MerrowFreeformSubgraphSnapshot * _Nullable subgraphs;
    size_t subgraph_count;
    MerrowFreeformNodeSnapshot * _Nullable nodes;
    size_t node_count;
    MerrowFreeformEdgeSnapshot * _Nullable edges;
    size_t edge_count;
} MerrowFreeformGraphSnapshot;

typedef NS_ENUM(NSInteger, MerrowFreeformGraphType) {
    MerrowFreeformGraphTypeFlowchart = 0,
    MerrowFreeformGraphTypeSequence = 1,
};

typedef NS_ENUM(NSInteger, MerrowFreeformInsertionKind) {
    MerrowFreeformInsertionKindNone = 0,
    MerrowFreeformInsertionKindNode = 1,
    MerrowFreeformInsertionKindSubgraph = 2,
    MerrowFreeformInsertionKindConnector = 3,
};

@class MerrowFreeformCanvasComponent;

@protocol MerrowFreeformCanvasComponentDelegate <NSObject>
- (void)freeformCanvasComponentDidChangeSelection:(MerrowFreeformCanvasComponent * _Nonnull)component;
@optional
- (void)freeformCanvasComponentDidMutateDocument:(MerrowFreeformCanvasComponent * _Nonnull)component;
@end

@interface MerrowFreeformCanvasComponent : NSView
@property (nonatomic, weak, nullable) id<MerrowFreeformCanvasComponentDelegate> delegate;
@property (nonatomic, readonly, assign) BOOL hasSelectedNode;
@property (nonatomic, readonly, assign) BOOL hasSelectedSubgraph;
@property (nonatomic, readonly, assign) BOOL hasSelectedEdge;
@property (nonatomic, readonly, assign) BOOL insertionModeActive;
@property (nonatomic, readonly, copy) NSString * _Nonnull selectionSummary;
@property (nonatomic, readonly, copy) NSString * _Nonnull insertionSummary;
@property (nonatomic, readonly, copy, nullable) NSString *selectedConnectableObjectId;
@property (nonatomic, readonly, strong) NSColor * _Nonnull canvasBackgroundColor;
@property (nonatomic, readonly, assign) CGFloat canvasBackgroundOpacity;
@property (nonatomic, readonly, assign) MerrowFreeformGraphType graphType;
@property (nonatomic, readonly, copy) NSString * _Nonnull selectedNodeLabel;
@property (nonatomic, readonly, strong) NSColor * _Nonnull selectedNodeFillColor;
@property (nonatomic, readonly, strong) NSColor * _Nonnull selectedNodeStrokeColor;
@property (nonatomic, readonly, assign) CGFloat selectedNodeStrokeWidth;
@property (nonatomic, readonly, assign) CGFloat selectedObjectWidth;
@property (nonatomic, readonly, assign) CGFloat selectedObjectHeight;
@property (nonatomic, readonly, copy) NSString * _Nonnull selectedEdgeLabel;
@property (nonatomic, readonly, strong) NSColor * _Nonnull selectedEdgeStrokeColor;
@property (nonatomic, readonly, assign) CGFloat selectedEdgeThickness;
@property (nonatomic, readonly, assign) NSInteger selectedEdgeLineStyle;
@property (nonatomic, readonly, assign) NSInteger selectedEdgeArrowMode;

- (void)loadEditableGraph:(const MerrowFreeformGraphSnapshot * _Nullable)graph;
- (void)clearDocument;
- (NSArray<NSDictionary *> * _Nonnull)connectableObjects;
- (void)beginInsertingNodeWithShape:(uint32_t)shape;
- (void)beginInsertingSubgraph;
- (BOOL)beginInsertingConnectorFromSelectedObject;
- (BOOL)beginInsertingConnectorFromObjectId:(NSString * _Nullable)sourceId;
- (void)cancelInsertionMode;
- (BOOL)createConnectorFromObjectId:(NSString * _Nullable)sourceId toObjectId:(NSString * _Nullable)targetId;
- (BOOL)writePNGExportToPath:(NSString * _Nonnull)path scale:(CGFloat)scale error:(NSError * _Nullable * _Nullable)error;
- (BOOL)writeSVGExportToPath:(NSString * _Nonnull)path scale:(CGFloat)scale error:(NSError * _Nullable * _Nullable)error;
- (void)updateCanvasBackgroundColor:(NSColor * _Nonnull)color;
- (void)updateCanvasBackgroundOpacity:(CGFloat)opacity;
- (void)updateSelectedNodeLabel:(NSString * _Nonnull)label;
- (void)updateSelectedNodeFillColor:(NSColor * _Nonnull)color;
- (void)updateSelectedNodeStrokeColor:(NSColor * _Nonnull)color;
- (void)updateSelectedNodeStrokeWidth:(CGFloat)strokeWidth;
- (void)updateSelectedObjectWidth:(CGFloat)width;
- (void)updateSelectedObjectHeight:(CGFloat)height;
- (void)updateSelectedEdgeLabel:(NSString * _Nonnull)label;
- (void)updateSelectedEdgeStrokeColor:(NSColor * _Nonnull)color;
- (void)updateSelectedEdgeThickness:(CGFloat)thickness;
- (void)updateSelectedEdgeLineStyle:(NSInteger)lineStyle;
- (void)updateSelectedEdgeArrowMode:(NSInteger)arrowMode;
- (nullable NSData *)serializedDocumentDataWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)loadSerializedDocumentData:(NSData * _Nonnull)data error:(NSError * _Nullable * _Nullable)error;
@end